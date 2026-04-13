# mac-reader

macOS 12-14向けのQRコードリーダー常駐プロセスです。

- USB COMモードデバイスをシリアルで監視
- 受信テキストをフォーカス中アプリへキーボード入力
- 1読取ごとに末尾改行を付与
- LaunchAgentで自動起動
- PKG生成スクリプト同梱

## 前提

- macOS 12, 13, 14
- Xcode Command Line Tools
- 実行時にアクセシビリティ許可が必要

## ビルド

```bash
cd mac-reader
swift build -c release
```

## PKG作成

```bash
cd mac-reader
chmod +x Scripts/build-pkg.sh Scripts/preinstall Scripts/postinstall Scripts/uninstall.sh
./Scripts/build-pkg.sh
```

生成物:

- dist/qr-reader-0.1.0.pkg

## インストール（ダブルクリック）

1. `dist/qr-reader-0.1.0.pkg` をダブルクリック
2. インストールウィザードが開くので「続ける」→「インストール」
3. 管理者パスワードを入力
4. 完了後、自動起動エージェントが即座に有効化されます

> **Gatekeeperで「開発元を確認できません」と表示された場合**  
> システム設定 → プライバシーとセキュリティ → 下部の「このまま開く」を押すか、  
> `xattr -d com.apple.quarantine dist/qr-reader-0.1.0.pkg` を実行してから再度ダブルクリック

## インストール後の確認

1. システム設定 → プライバシーとセキュリティ → アクセシビリティ で  
   `/usr/local/libexec/com.company.qrreader/qr-reader-daemon` を許可
2. QRリーダーをUSB接続
3. テキスト入力欄（メモアプリ等）にフォーカスしてQRを読む
4. 1読取ごとに1行で入力されることを確認

## 設定値

LaunchAgent内の環境変数で設定できます。

- QR_BAUD: 9600
- QR_DATABITS: 8
- QR_PARITY: N
- QR_STOPBITS: 1
- QR_DEDUPE_WINDOW_SEC: 0.35
- QR_LINE_ENDING: \n
## アンインストール

```bash
sudo Scripts/uninstall.sh
```
