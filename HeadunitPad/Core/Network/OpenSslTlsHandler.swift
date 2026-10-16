//
//  OpenSslTlsHandler.swift
//  HeadunitPad
//
//  TLS implementation using OpenSSL
//  Mirrors Android's AapSslNative approach using native OpenSSL
//

import Foundation
import OpenSSL

struct OpenSslHandshakeStep {
    let outgoingData: Data
    let isComplete: Bool
}

enum OpenSslTlsError: Error {
    case contextCreationFailed
    case handshakeFailed(String)
    case connectionFailed
    case sslError(Int32)
    case timeout
    case invalidState
    case bioError(String)
}

class OpenSslTlsHandler {
    private static let bioSetWriteBufSizeCmd: Int32 = 136 // BIO_C_SET_WRITE_BUF_SIZE

    private var sslContext: OpaquePointer?
    private var ssl: OpaquePointer?
    private var readBio: OpaquePointer?
    private var writeBio: OpaquePointer?
    private(set) var isHandshakeComplete = false
    private var clientCertificate: OpaquePointer?
    private var clientPrivateKey: OpaquePointer?
    private var certPath: String?
    private var keyPath: String?
    private var decryptScratchBuffer = [UInt8](repeating: 0, count: 65536)

    init() {}

    func setup() -> Bool {
        OPENSSL_init_ssl(0, nil)

        sslContext = SSL_CTX_new(TLS_client_method())
        guard sslContext != nil else {
            AppLog.e("Failed to create SSL context", tag: "OpenSslTls")
            return false
        }

        SSL_CTX_set_verify(sslContext, SSL_VERIFY_NONE, nil)

        AppLog.i("SSL context created", tag: "OpenSslTls")
        return true
    }

    func loadCertificate(certPath: String, keyPath: String) -> Bool {
        guard sslContext != nil else { return false }

        let result = SSL_CTX_use_certificate_file(sslContext, certPath, SSL_FILETYPE_PEM)
        guard result == 1 else {
            AppLog.e("Failed to load certificate: \(result)", tag: "OpenSslTls")
            return false
        }

        let keyResult = SSL_CTX_use_PrivateKey_file(sslContext, keyPath, SSL_FILETYPE_PEM)
        guard keyResult == 1 else {
            AppLog.e("Failed to load private key: \(keyResult)", tag: "OpenSslTls")
            return false
        }

        let verifyResult = SSL_CTX_check_private_key(sslContext)
        guard verifyResult == 1 else {
            AppLog.e("Private key does not match certificate", tag: "OpenSslTls")
            return false
        }

        self.certPath = certPath
        self.keyPath = keyPath

        loadClientIdentityIntoMemory(certPath: certPath, keyPath: keyPath)

        AppLog.i("Certificate and key loaded", tag: "OpenSslTls")
        return true
    }

    func hasClientIdentity() -> Bool {
        return certPath != nil && keyPath != nil
    }

    @discardableResult
    func loadDefaultBundleCertificate() -> Bool {
        if hasClientIdentity() { return true }
        let bundles = [Bundle.main, Bundle(for: OpenSslTlsHandler.self)]
        let candidateSubdirs: [String?] = [
            "HeadunitPad/Resources/Raw",
            "Resources/Raw",
            "Raw",
            nil
        ]
        var foundCert: String?
        var foundKey: String?
        for b in bundles {
            for dir in candidateSubdirs {
                if foundCert == nil, let p = b.path(forResource: "cert", ofType: nil, inDirectory: dir), FileManager.default.fileExists(atPath: p) {
                    foundCert = p
                }
                if foundKey == nil, let p = b.path(forResource: "privkey", ofType: nil, inDirectory: dir), FileManager.default.fileExists(atPath: p) {
                    foundKey = p
                }
            }
        }
        guard let cert = foundCert, let key = foundKey else { return false }
        return loadCertificate(certPath: cert, keyPath: key)
    }

    func startHandshakeSession() throws -> OpenSslHandshakeStep {
        guard sslContext != nil else {
            throw OpenSslTlsError.contextCreationFailed
        }
        if certPath == nil || keyPath == nil {
            _ = loadDefaultBundleCertificate()
        }

        releaseSessionOnly()
        isHandshakeComplete = false

        ssl = SSL_new(sslContext)
        guard ssl != nil else {
            throw OpenSslTlsError.contextCreationFailed
        }

        if let cert = clientCertificate {
            let certSetResult = SSL_use_certificate(ssl, cert)
            AppLog.i("SSL_use_certificate result=\(certSetResult)", tag: "OpenSslTls")
        }
        if let pkey = clientPrivateKey {
            let keySetResult = SSL_use_PrivateKey(ssl, pkey)
            AppLog.i("SSL_use_PrivateKey result=\(keySetResult)", tag: "OpenSslTls")
        }

        // Fallback: if in-memory identity is unavailable, bind cert/key from PEM files per session.
        if SSL_get_certificate(ssl) == nil {
            if let certPath = certPath {
                let certFileResult = SSL_use_certificate_file(ssl, certPath, SSL_FILETYPE_PEM)
                AppLog.i("SSL_use_certificate_file result=\(certFileResult)", tag: "OpenSslTls")
            }
            if let keyPath = keyPath {
                let keyFileResult = SSL_use_PrivateKey_file(ssl, keyPath, SSL_FILETYPE_PEM)
                AppLog.i("SSL_use_PrivateKey_file result=\(keyFileResult)", tag: "OpenSslTls")
            }
        }

        let sessionKeyCheck = SSL_check_private_key(ssl)
        AppLog.i("SSL_check_private_key(session) result=\(sessionKeyCheck)", tag: "OpenSslTls")
        let sslCert = SSL_get_certificate(ssl)
        AppLog.i("Session cert present=\(sslCert != nil)", tag: "OpenSslTls")

        readBio = BIO_new(BIO_s_mem())
        writeBio = BIO_new(BIO_s_mem())
        guard readBio != nil && writeBio != nil else {
            throw OpenSslTlsError.bioError("Failed to create BIO")
        }

        setBioWriteBufferSize(readBio, size: AapMessage.DEF_BUFFER_LENGTH)
        setBioWriteBufferSize(writeBio, size: AapMessage.DEF_BUFFER_LENGTH)

        SSL_set0_rbio(ssl, readBio)
        SSL_set0_wbio(ssl, writeBio)
        SSL_set_connect_state(ssl)
        SSL_set_verify(ssl, SSL_VERIFY_NONE, nil)

        AppLog.i("Handshake session prepared", tag: "OpenSslTls")
        return try runHandshakeStep()
    }

    func continueHandshake(with incomingTlsData: Data) throws -> OpenSslHandshakeStep {
        guard !isHandshakeComplete else {
            return OpenSslHandshakeStep(outgoingData: Data(), isComplete: true)
        }
        guard readBio != nil else {
            throw OpenSslTlsError.invalidState
        }

        if !incomingTlsData.isEmpty {
            let written = BIO_write(readBio, (incomingTlsData as NSData).bytes, Int32(incomingTlsData.count))
            if written <= 0 {
                throw OpenSslTlsError.bioError("BIO_write failed while feeding handshake data")
            }
            AppLog.i("Fed \(written) handshake bytes into read BIO", tag: "OpenSslTls")
        }

        return try runHandshakeStep()
    }

    private func runHandshakeStep() throws -> OpenSslHandshakeStep {
        guard let ssl = ssl else {
            throw OpenSslTlsError.invalidState
        }

        var outgoing = Data()
        var iterations = 0

        while iterations < 8 {
            let result = SSL_do_handshake(ssl)
            drainWriteBio(into: &outgoing)

            if result == 1 {
                isHandshakeComplete = true
                AppLog.i("Handshake complete", tag: "OpenSslTls")
                return OpenSslHandshakeStep(outgoingData: outgoing, isComplete: true)
            }

            let err = SSL_get_error(ssl, result)
            AppLog.w("SSL_do_handshake result=\(result) err=\(err)", tag: "OpenSslTls")

            if err == SSL_ERROR_WANT_READ {
                return OpenSslHandshakeStep(outgoingData: outgoing, isComplete: false)
            }
            if err == SSL_ERROR_WANT_WRITE {
                iterations += 1
                continue
            }

            throw OpenSslTlsError.sslError(err)
        }

        return OpenSslHandshakeStep(outgoingData: outgoing, isComplete: false)
    }

    private func drainWriteBio(into output: inout Data) {
        guard let writeBio = writeBio else { return }

        while true {
            let pending = BIO_ctrl_pending(writeBio)
            if pending <= 0 {
                return
            }

            var buffer = [UInt8](repeating: 0, count: Int(pending))
            let read = BIO_read(writeBio, &buffer, Int32(pending))
            if read <= 0 {
                return
            }
            output.append(contentsOf: buffer[0..<Int(read)])
        }
    }

    private func setBioWriteBufferSize(_ bio: OpaquePointer?, size: Int) {
        guard let bio = bio else { return }
        let ret = BIO_ctrl(bio, OpenSslTlsHandler.bioSetWriteBufSizeCmd, size, nil)
        if ret <= 0 {
            AppLog.e("Failed to set BIO write buffer size to \(size)", tag: "OpenSslTls")
        }
    }

    func encrypt(data: Data) -> Data? {
        guard let ssl = ssl, isHandshakeComplete else { return nil }
        guard !data.isEmpty else { return nil }

        let written = data.withUnsafeBytes { rawPtr -> Int32 in
            guard let base = rawPtr.baseAddress else { return 0 }
            return SSL_write(ssl, base, Int32(data.count))
        }
        guard written > 0 else { return nil }

        var encrypted = Data()
        drainWriteBio(into: &encrypted)

        return encrypted.isEmpty ? nil : encrypted
    }

    func decrypt(data: Data) -> Data? {
        guard let ssl = ssl, isHandshakeComplete else { return nil }
        guard !data.isEmpty else { return nil }

        let written = data.withUnsafeBytes { rawPtr -> Int32 in
            guard let base = rawPtr.baseAddress else { return 0 }
            return BIO_write(readBio, base, Int32(data.count))
        }
        guard written > 0 else { return nil }

        var decrypted = Data()

        while true {
            let read = SSL_read(ssl, &decryptScratchBuffer, Int32(decryptScratchBuffer.count))
            if read > 0 {
                decrypted.append(contentsOf: decryptScratchBuffer[0..<Int(read)])
                continue
            }

            let err = SSL_get_error(ssl, read)
            if err == SSL_ERROR_WANT_READ || err == SSL_ERROR_WANT_WRITE {
                break
            }
            if read <= 0 {
                break
            }
        }

        return decrypted.isEmpty ? nil : decrypted
    }

    func postHandshakeReset() {
    }

    func release() {
        releaseSessionOnly()
        isHandshakeComplete = false

        if let cert = clientCertificate {
            X509_free(cert)
            clientCertificate = nil
        }
        if let pkey = clientPrivateKey {
            EVP_PKEY_free(pkey)
            clientPrivateKey = nil
        }

        if let ctx = sslContext {
            SSL_CTX_free(ctx)
            sslContext = nil
        }
    }

    func releaseSessionOnly() {
        if let ssl = ssl {
            SSL_free(ssl)
        }
        ssl = nil
        readBio = nil
        writeBio = nil
        isHandshakeComplete = false
    }

    private func loadClientIdentityIntoMemory(certPath: String, keyPath: String) {
        if let cert = clientCertificate {
            X509_free(cert)
            clientCertificate = nil
        }
        if let pkey = clientPrivateKey {
            EVP_PKEY_free(pkey)
            clientPrivateKey = nil
        }

        guard let certData = try? Data(contentsOf: URL(fileURLWithPath: certPath)) else {
            AppLog.e("Failed to read certificate data from path", tag: "OpenSslTls")
            return
        }
        guard let keyData = try? Data(contentsOf: URL(fileURLWithPath: keyPath)) else {
            AppLog.e("Failed to read private key data from path", tag: "OpenSslTls")
            return
        }

        let certBio = BIO_new_mem_buf((certData as NSData).bytes, Int32(certData.count))
        guard certBio != nil else {
            AppLog.e("Failed to create certificate BIO", tag: "OpenSslTls")
            return
        }
        defer { BIO_free(certBio) }

        let keyBio = BIO_new_mem_buf((keyData as NSData).bytes, Int32(keyData.count))
        guard keyBio != nil else {
            AppLog.e("Failed to create key BIO", tag: "OpenSslTls")
            return
        }
        defer { BIO_free(keyBio) }

        var certOut: OpaquePointer?
        let cert = PEM_read_bio_X509_AUX(certBio, &certOut, nil, nil)
        guard cert != nil else {
            AppLog.e("PEM_read_bio_X509_AUX failed", tag: "OpenSslTls")
            return
        }

        var keyOut: OpaquePointer?
        let pkey = PEM_read_bio_PrivateKey(keyBio, &keyOut, nil, nil)
        guard pkey != nil else {
            AppLog.e("PEM_read_bio_PrivateKey failed", tag: "OpenSslTls")
            X509_free(cert)
            return
        }

        clientCertificate = cert
        clientPrivateKey = pkey
        AppLog.i("Loaded client identity into memory", tag: "OpenSslTls")
    }
}