# Too Much Chrome

> [中文](README.md) · [English](README.en.md) · [公式サイト](https://acerola-1.github.io/too-much-chrome/)

<p align="center">
  <img src="docs/images/icon.png" width="132" alt="Too Much Chrome icon">
</p>

<p align="center">
  <strong>あなたの Mac に、Web エンジンアプリがいくつ隠れているか。</strong>
</p>

<p align="center">
  Too Much Chrome は macOS 上の Chromium / WebView ベースのアプリ——Electron、CEF、NW.js、
  Tauri、Wails、そして Chrome・Edge・Brave などのフルブラウザ——をすべてスキャンし、
  ストレージ容量とエンジンのバージョン健康度を計測します。名前はネタ。スキャンは本気。
</p>

<p align="center">
  <a href="https://github.com/acerola/too-much-chrome/releases/latest"><strong>最新版をダウンロード</strong></a> ·
  <a href="https://acerola-1.github.io/too-much-chrome/"><strong>公式サイト</strong></a> ·
  <a href="#機能ハイライト">機能ハイライト</a> ·
  <a href="#インストール">インストール</a> ·
  <a href="#システム要件">システム要件</a> ·
  <a href="#ビルド">ビルド</a>
</p>

<p align="center">
  <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-111827?style=flat-square&logo=apple">
  <img alt="Apple Silicon" src="https://img.shields.io/badge/Apple%20Silicon-M%20series-2ECC71?style=flat-square&logo=apple">
  <img alt="Swift" src="https://img.shields.io/badge/Swift-SwiftUI-F05138?style=flat-square&logo=swift&logoColor=white">
  <img alt="License" src="https://img.shields.io/badge/license-AGPL--3.0-blue?style=flat-square">
  <img alt="SwiftPM" src="https://img.shields.io/badge/SwiftPM-5.9-orange?style=flat-square&logo=swift">
</p>

## スクリーンショット

### スキャン結果のメイン画面

フローティングガラスのツールバーとレポートパネルが同じラインに並びます。グリッドには
見つかった順にアプリが次々と表示され、スキャンラインの光の位置がそのまま進捗バー。
右側のパネルには総数、ストレージ内訳、タイプ別ドーナツチャート、上位 5 件、
バージョン健康度が一目で収まります。

<p align="center">
  <img src="docs/images/app-hero.png" width="720" alt="Too Much Chrome スキャン結果のメイン画面">
</p>

## 機能ハイライト

### 本物のスキャン

`/Applications` と `~/Applications` 直下の `.app` を列挙。Electron / CEF / NW.js は
`Contents/Frameworks` のディレクトリ名と plist の Bundle ID の二重シグナルで判別し、
ほぼ 100% の精度——リネームビルド（例: QQNT.framework）も `com.github.Electron.framework`
を保持するため、ディレクトリ名に加えた第二の特徴になります。Tauri / Wails は Bundle ID /
リソースディレクトリのキーワードとメインバイナリ内のビルドパス痕跡を使い、
実験的であることを正直に表示します。

### 容量の計測

アプリ本体の再帰的な割り当てサイズに加え、`~/Library` 配下のユーザーデータ
（Application Support / Caches / Containers / WebKit / Saved Application State / Logs）を
Bundle ID とアプリ名で二重照合し、重複を除いて集計します。

### バージョン健康度

公式ソース（Electron は npm registry、Chromium は Google VersionHistory、Tauri は crates.io、
Wails は Go module proxy）のオンラインベースラインと照合して 5 段階（緑 → 赤）で判定。
ベースラインは 24 時間キャッシュされ、ソースごとにキャッシュ値へ、最後は内蔵アンカーへ
フォールバックするので、オフラインでもそのまま使えます。

### スキャンライン演出

コピー機のスキャンラインが実際のスキャン進捗と連動。光の位置がそのまま進捗バーになり、
アプリが見つかるたびにアイコンがぼやけから現れます。「視差効果を減らす」が有効な場合は
自動的にスキップされます。

### レポートパネルと詳細ポップオーバー

アプリをクリックするとストレージ内訳とインストールパスを表示し、Finder で表示も
ワンクリック。ランキング行とグリッドのアイコンは連動ハイライトし、`⌘R` でいつでも
再スキャンできます。

### Swift ネイティブ、一回きりのタスク

Swift / SwiftUI で開発。macOS 26 では Liquid Glass が自動で有効になり（旧バージョンは
すりガラス素材にフォールバック）、スキャンはバックグラウンドスレッドで実行され、
メインスレッドは結果の表示だけを担当します。スキャンしたら終了、常駐プロセスはありません。

## インストール

1. [Releases](https://github.com/acerola/too-much-chrome/releases/latest) から最新の `.dmg` をダウンロード
2. DMG を開いて Too Much Chrome を Applications フォルダへドラッグ
3. Launchpad または Applications から起動。最初のスキャンが自動で始まります

アプリは Apple の公証済みで、ダウンロード後にそのまま開けます。

## システム要件

- macOS 14 以降（macOS 26+ では Liquid Glass が有効）
- Apple Silicon（M シリーズチップ）

## ビルド

SwiftPM プロジェクトです。Xcode で `Package.swift` を開いて開発できます:

```bash
./launch.sh            # .app をビルドして起動（scripts/build-app.sh dev を実行）
./launch.sh cli        # ヘッドレススキャン CLI（tmc-scan）をビルドして実行
swift build            # 全ターゲットをコンパイル
swift test             # ユニットテスト
swift run tmc-scan --online   # ヘッドレススキャン（オンラインベースライン判定）
```

配布（Developer ID 署名 + Apple 公証 + DMG）は `scripts/build-app.sh` で行います:

```bash
./scripts/build-app.sh release    # .app を組み立て + Developer ID 署名（ハードニング + タイムスタンプ）
./scripts/build-app.sh notarize   # Apple 公証に提出してチケットをステープル
./scripts/build-app.sh dmg        # DMG を生成して公証（配布物）
```

リリースは `scripts/release.sh` で駆動します: バージョン更新 → リリースノート生成 →
main へマージ → タグ付け → GitHub Actions がビルド・署名・公証・Release 公開まで実行
（`.github/workflows/release.yml` を参照）。

## Star History

<p align="center">
  <a href="https://star-history.com/#acerola/too-much-chrome&Date">
    <picture>
      <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=acerola/too-much-chrome&type=Date&theme=dark" />
      <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/svg?repos=acerola/too-much-chrome&type=Date" />
      <img alt="Star History Chart" src="https://api.star-history.com/svg?repos=acerola/too-much-chrome&type=Date" width="720" />
    </picture>
  </a>
</p>

<p align="center">
  このプロジェクトが役に立ったなら、⭐ で継続開発を応援してください。
</p>

## ライセンス

本プロジェクトは **GNU AGPL-3.0** デュアルライセンスです:

- **オープンソース利用**: ソースは公開され、[AGPL-3.0](LICENSE) の条件のもとで自由に
  閲覧・改変・配布できます。AGPL の要求により、派生物（ネットワークサービスとして提供する
  場合を含む）も AGPL-3.0 で完全なソースを公開する必要があります。
- **商用利用**: **AGPL のコピーレフト義務に従わず**に商用製品へ利用する場合（例:
  クローズドソースでの配布、ソース非公開での有料配布）は、**商用ライセンスの取得が必要**です。
  [GitHub](https://github.com/acerola/too-much-chrome) の Issue または作者への連絡でご相談ください。

Copyright © 2026 Acerola. All rights reserved.

### サードパーティコンポーネント

本プロジェクトにサードパーティ依存はありません。システムフレームワーク
（SwiftUI / AppKit / Foundation）のみを使用しています。
