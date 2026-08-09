# HeadunitPad Wired Android Auto Product Requirements Document

## 1. Product goal

讓 HeadunitPad 在透過 TrollStore 安裝於支援的 iPadOS 裝置後，可以由 iPad 擔任 USB Host，透過資料線將 Android 手機切換至 Android Open Accessory（AOA）模式，並以 USB bulk endpoints 承載既有 Android Auto Protocol（AAP）連線。

完成後，使用者應能在保留現有無線連線功能的情況下，選擇或自動使用有線 USB 連線，並沿用現有的影片、音訊、觸控、麥克風與定位功能。

## 2. Source and compatibility assumptions

- USB Host 能力由遠端 Swift package [TrollUSBHostKit](https://github.com/andyching168/TrollUSBHostKit) 提供；不得在本專案重新 vendoring libusb。
- App 目前 deployment target 為 iOS/iPadOS 16.6，除非使用者明確同意，不得為了整合套件直接提高最低版本。
- TrollUSBHostKit 目前宣告最低 iOS 17；Phase 1 必須先讓遠端套件提供可被本專案 iOS 16.6 target 合法解析與建置的 tagged release。
- 目標安裝方式為 TrollStore。一般 App Store、一般免費開發者簽章與未具備所需 private entitlements 的安裝方式不在本功能保證範圍內。
- 真機驗收以具有 USB Host 能力、安裝 TrollStore 的 iPad 與支援 Android Auto/AOA 的 Android 手機為準。

## 3. User-visible requirements

### 3.1 Connection modes

設定畫面必須提供以下連線模式：

- `Auto`：優先嘗試已接上的可用 USB Android 裝置；沒有可用 USB 時沿用既有無線探索流程。
- `Wired USB`：只執行 USB 探索、AOA 切換與有線 AAP 連線，不啟動無線探索。
- `Wireless Helper`：保留既有行為。
- `Direct Headunit Server`：保留既有行為。

切換模式在下一次連線時生效，不得破壞既有設定持久化。

### 3.2 Wired connection flow

1. App 在背景啟動 USB Host controller 並列舉已接裝置。
2. 對尚未進入 accessory mode 的 Android 裝置執行 AOA 協商：
   - vendor IN request 51，讀取 protocol version；
   - vendor OUT request 52，依序傳送 Android Auto head-unit identity：manufacturer `Android`、model `Android Auto`、description `Android Auto`、version `2.0.1`、URI `https://developer.android.com/auto/index.html`、serial `HU-AAAAAA001`；
   - vendor OUT request 53，要求進入 accessory mode。
3. request 53 後，手機可能在 control transfer 回覆前斷線；若已送出 START，立即 detach 必須被視為等待重新枚舉，而不是 App crash。
4. 手機重新枚舉為 Google accessory device 後，App 找出同一 interface 上的一組 bulk IN 與 bulk OUT endpoints，並 claim 該 interface。
5. USB byte stream 接入既有 AAP version handshake、TLS、authentication、binding 與媒體流程。
6. 拔線、裝置 detach、transfer timeout 或使用者取消時，App 必須停止 pending transfers、釋放 session，並回到可再次連線的狀態。

### 3.3 Status and diagnostics

使用者必須能辨識目前是 USB 或無線連線。USB 流程至少應顯示：

- 正在搜尋 USB 裝置；
- 正在切換 Android accessory mode；
- 正在等待 USB 重新連線；
- 正在執行 Android Auto handshake；
- 已透過 USB 連線；
- 可理解的 USB 權限、裝置、interface、timeout 或 detach 錯誤。

診斷資訊至少包含 connection kind、USB VID/PID、bus/address、AOA protocol version、interface number、bulk IN/OUT endpoint，以及可取得時的 TrollUSBHostKit libusb log。

## 4. Architecture requirements

### 4.1 Transport boundary

- `AapTransport` 不得直接依賴 `TcpHandler`。
- 建立一個最小 byte-stream connection protocol，統一提供連線狀態、send、disconnect 與 receive/connect/disconnect callbacks。
- `TcpHandler` 與新的 USB connection adapter 都必須實作相同 protocol。
- AAP framing、TLS、channel handling、影片、音訊、觸控、麥克風與定位邏輯不得因 transport 類型而複製兩份。
- 現有未被使用的 blocking `AccessoryConnection`/`TcpAccessoryConnection` 可以被最小幅度調整或替換，但不得保留兩套互相競爭的 transport 抽象。

### 4.2 USB modules

USB 功能至少分成：

- AOA negotiation：負責 request 51/52/53 與重新枚舉狀態。
- USB accessory connection：負責 interface/endpoint 選擇、claim、bulk read/write 與 session lifecycle。
- Connection orchestration：由 `ConnectionManager` 決定 USB/無線模式與將 connection 注入 `AapTransport`。

AOA 與 endpoint 選擇邏輯應盡可能是可單元測試的純 Swift 邏輯。不得在 UI 主執行緒執行 USB enumeration、control transfer、bulk transfer 或等待重新枚舉。

### 4.3 Transfer behavior

- USB receive loop 使用 TrollUSBHostKit 的 async bulk read，不得自行阻塞主執行緒。
- 收到的 USB chunk 不等同於一個完整 AAP frame；必須交由既有 receive buffer 組框。
- partial-timeout 中實際已收到的 bytes 不得丟棄。
- writes 必須序列化；一次 AAP packet 的 bytes 不得與另一筆 write 交錯。
- cancellation、detach 與 disconnect 不得讓 continuation 重複完成、hang 或造成 use-after-free。
- USB 非核心診斷失敗不得使已建立的 AAP session crash。

## 5. Signing and packaging requirements

App target 必須包含：

```xml
<key>com.apple.vm.device-access</key>
<true/>
<key>com.apple.security.exception.iokit-user-client-class</key>
<array>
    <string>AppleUSBHostDeviceUserClient</string>
    <string>AppleUSBHostInterfaceUserClient</string>
</array>
<key>com.apple.system.diagnostics.iokit-properties</key>
<true/>
```

- `com.apple.system.diagnostics.iokit-properties` 是實機列舉所需：沒有它時 IORegistry 雖可看到 USB service 名稱，但 `idVendor`、`idProduct`、`sessionID` 與 `locationID` 等屬性不可見，libusb 無法建立可列舉裝置。
- 只加入以上三項 TrollUSBHostKit 實機路徑所需的 entitlements；不得自行加入 root helper、platform-application 或其他 unsandbox entitlement。
- TrollStore IPA workflow 必須在 App executable 上實際套用 entitlements，而不是只建立 unsigned `.app` 後壓縮。
- workflow 必須在封裝前重新讀回 executable entitlements，缺少任一必要 key 時建置失敗。
- IPA 仍需包含現有 App 資源與 CocoaPods frameworks。
- 因 TrollUSBHostKit 靜態連結 vendored libusb，發布 binary 時必須在專案文件或發行說明提供對應原始碼、LGPL-2.1 notice 與 relinking 說明的入口。

## 6. Scope

### 6.1 In scope

- TrollUSBHostKit tagged dependency 與 iOS 16.6 compatibility gate。
- TrollStore entitlements 與可重現 IPA workflow。
- AOA accessory mode negotiation。
- USB hotplug/re-enumeration、interface claim、bulk IN/OUT transport。
- 將既有 AAP stack transport-neutral 化。
- Auto/Wired USB 模式、狀態文字與 USB 診斷。
- 單元測試、build checks 與真機驗收紀錄。

### 6.2 Out of scope

- 修改或逆向 Android Auto application protocol 本身，除非實機證據顯示既有 AAP 行為與 USB transport 不相容。
- 新增 ADB、scrcpy、CarPlay、USB audio class 或 HID 功能。
- 一般 App Store 發布。
- 自動安裝 TrollStore、修改系統、root helper 或 jailbreak 功能。
- 為不支援 AOA 的手機提供廠商專用 USB driver。
- 與有線功能無關的 UI 重設計或既有無線功能重構。

## 7. Delivery phases

一次只能有一個 active task；每個 task 的驗證證據記錄到兩份 harness 檔後才能前進。

### Phase 1 — Package and signing foundation

1. 讓 TrollUSBHostKit 提供可供 iOS 16.6 consumer 使用、完成 standalone iOS build 驗證的 tagged release，並將 HeadunitPad 加入該遠端 dependency。
2. 新增 App entitlements，設定 target signing，修正 TrollStore IPA workflow 以套用並驗證 entitlements。

Gate：HeadunitPad simulator build 與 generic iOS device build 成功；產出的 IPA executable 可讀回三項必要 USB entitlements；既有無線 App 可正常啟動。

### Phase 2 — AOA probe and mode switch

1. 建立可測試的 AOA request/identity model 與 negotiation sequence。
2. 用 TrollUSBHostKit 列舉裝置、執行 request 51/52/53，並等待 accessory device 重新枚舉。
3. 加入最小 USB 診斷與錯誤狀態，暫時不接入完整 AAP。

Gate：在 TrollStore 安裝的真機 App 中，能記錄一般模式手機、有效 AOA protocol version、START、detach，以及 accessory mode 重新枚舉後的 VID/PID/interface/endpoints。無 USB 裝置或不支援 AOA 時不得 crash。

### Phase 3 — USB transport and AAP cutover

1. 建立共用 byte-stream transport boundary，讓既有 TCP 路徑改走該介面且行為不變。
2. 實作 USB accessory connection 的 interface claim、bulk read/write、detach/cancel lifecycle。
3. 將 USB connection 注入既有 AAP stack，完成 version、TLS、authentication 與 binding。

Gate：無線回歸測試通過；有線 session 到達 AAP running；拔線不 crash 且能再次連線。

### Phase 4 — Product integration and acceptance

1. 加入 `Wired USB` 與 USB-first `Auto` 模式、狀態文字與 diagnostics。
2. 驗證有線影片、音訊、觸控、麥克風與定位。
3. 完成重複拔插、前背景切換與長時間連線測試，補齊 README 與 LGPL 發行說明。

Gate：真機完成完整功能矩陣；連續拔插至少 10 次、背景/前景恢復及至少 30 分鐘播放不 crash；最終 TrollStore IPA 可重現建置與安裝。

## 8. Test strategy

### 8.1 Automated tests

- AOA request order、request type、index、payload 與 protocol version parsing。
- request 53 後立即 detach 的狀態轉移。
- accessory VID/PID 與 bulk IN/OUT endpoint selection。
- receive chunk fragmentation/aggregation 不改變 AAP framing。
- serialized writes、cancel、detach 與 reconnect lifecycle。
- TCP transport regression。
- TrollUSBHostKit `swift test`。
- HeadunitPad simulator 與 generic iOS builds。
- IPA entitlement extraction assertion。

### 8.2 Physical tests

- 使用實際 TrollStore 安裝的 IPA，不得以 simulator 或單元測試替代 USB Host 驗收。
- 記錄 iPad 型號、iPadOS 版本、TrollStore 版本、手機型號/Android 版本、線材與是否使用供電 hub。
- 驗證初始枚舉、AOA 切換、accessory endpoints、AAP running、影音輸入輸出與安全 detach。
- 直接 USB-C 連線若因供電或 role negotiation 不穩，需另外以供電 hub 重測並記錄差異，不得把未驗證推測寫成已完成。

## 9. Completion criteria

只有同時符合以下條件才可宣告整體完成：

- 所有 Phase gate 均有程式碼與驗證證據。
- TrollStore IPA 內含正確 entitlements，且真機能取得 USB Host 存取。
- Android 手機可由一般模式切換成 accessory mode 並進入有線 AAP running。
- 影片、音訊、觸控、麥克風與定位在有線模式下通過驗收。
- 既有 Wireless Helper 與 Direct Headunit Server 功能沒有回歸。
- detach/reconnect、前背景與長時間測試符合 Phase 4 gate。
- README、第三方授權入口、progress 與 handoff 與實際狀態一致。
