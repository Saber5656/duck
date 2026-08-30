# duck 設計書 (v1)

- Repository: `github.com/Saber5656/duck`
- Tagline: "A rubber-duck debugging companion that listens and responds with gentle backchannels."
- License: MIT（前提）/ クラウド送信なし / 個人 OSS・最小実装で早期リリース
- 作成日: 2026-07-05

---

## 1. コンセプト

duck は、デスクトップの隅に住む小さなアヒルである。ユーザーがバグについて声に出して説明している間、
アヒルはうなずいて聞く。黙ると小首をかしげて続きを待ち、長い説明を終えると大きくうなずいて応える。
それだけのアプリであり、**内容は一言も理解しない**。

rubber duck debugging の効能は「説明する行為そのもの」にある。相手が賢い必要はなく、
むしろ答えを返さないことに価値がある。duck はこれを設計原理に昇華する：
**マイクから取るのは音量 1 個の数値だけ。音声認識も録音も送信も、コード上も OS 制約上も不可能な構造にする。**
「聞いてくれている感」を最大化し、「聞かれている不安」をゼロにする。

**既存の類似プロダクトとの位置づけ**

| 既存 | 形態 | duck との違い |
|---|---|---|
| 物理のラバーダック（rubberduckdebugging.com 等） | 机の上 | 反応しない。duck は話している間だけうなずき、「聞いている」フィードバックを返す |
| AI 型 duck（Rubber Duck Debug Assistant 等） | Web / AI チャット | AI が答えを返す＝「自分で気づく」という本質から離れ、テキスト入力は「声に出す」でもない。duck は**理解しないこと**を機能として売る |
| Quack The Code | Electron デスクトップ | Chromium 同梱で重い。duck はゼロ依存ネイティブ数 MB |
| rdd（Google Play のうなずくアヒル） | モバイル | スマホを机に置く必要がある。duck は作業中のデスクトップ隅に常駐し、手を止めさせない |

存在理由は一文で言える：**"It listens, but never understands — that's the point."**
音声を扱うのに STT を積まないという逆張りが、プライバシー主張とコンセプトの両方を同時に成立させる。

---

## 2. v1 スコープ

| 区分 | 項目 | 理由 |
|---|---|---|
| 入れる | 音量ベース VAD（閾値 + attack + hangover + 適応ノイズフロア） | コア。内容を見ずに「話している/黙った」だけを検出する（§5） |
| 入れる | 相槌アニメ 5 状態（idle / nodding / tilt / bigNod / sleep） | 「聞いてくれている」体験の最小完全セット |
| 入れる | メニューバー常駐 + **Listening を 1 クリックで on/off** | off は duck によるマイク完全解放（エンジン停止）。Control Center から duck が消える状態と同期（§7.3） |
| 入れる | デスクトップ隅の小窓スプライト（四隅から選択、クリックスルー） | cursorpets の小窓方式を流用。作業の邪魔をしない |
| 入れる | 初回起動オンボーディング（プライバシー説明 + 権限誘導 + 拒否時デモモード） | マイク権限が取れないと何も起きないアプリ。初回体験＝製品体験 |
| 入れる | Sensitivity 3 段階（Low / Medium / High） | 環境ノイズ差への最低限の適応。連続値スライダーは作らない |
| 入れる | App Sandbox + network entitlement なし + privacy-guard CI | 「送信できないことを OS が強制する」keycat 方式（§7） |
| 入れる | GitHub Releases + Homebrew tap、署名 + notarization | 導入 1 行（§8） |
| 入れない | STT・音声認識・キーワード反応・AI 応答 | **恒久的に入れない。** コンセプトの核。入れた瞬間にプライバシー設計と存在理由が崩れる |
| 入れない | 鳴き声（クワッ）等の効果音 | duck が反応する場面＝ユーザーが話している場面＝**通話・会議中の可能性が構造的に高い**。そこで音を出すのは事故の作り込み。ミュート設計も芋づるで増える。v2 で安全な形（手動時のみ等）を検討 |
| 入れない | カーソル追跡・画面内移動 | cursorpets と役割が違う。duck は聞き役として鎮座する |
| 入れない | 録音レベルメータ表示 | RMS 値の UI 露出を避け、プライバシー境界（§5）を単純に保つ。感度調整は 3 段プリセットで足りる |
| 入れない | 複数ダック・スキン・サイズ選択 | スプライト仕様（duck.json）だけ固定して v2 の口を残す |
| 入れない | 表示ディスプレイ選択 | メニューバーのあるメインディスプレイ固定。外部モニタ主体ならそれがメインになるため実害が小さい |
| 入れない | 無音 N 分で自動 Listening off | 「勝手に聞くのをやめる」は体験を裏切る。省電力実測を見て v2 判断 |
| 入れない | Windows / Linux 対応 | §3 参照 |
| 入れない | 自動更新（Sparkle） | ネットワーク不使用の主張を保つ。brew upgrade で十分 |

---

## 3. 対応プラットフォームと優先順位

| 優先度 | OS | 判断 | 理由 |
|---|---|---|---|
| 1 (v1) | macOS 13+ (Apple Silicon / Intel Universal) | 対応 | 開発者の環境。AVAudioEngine・sandbox・署名・オレンジインジケータまで一人で検証と配布が完結する |
| 2 (v2 候補) | Windows 10/11 | 保留 | WASAPI のピークメータ（IAudioMeterInformation）で同等の音量監視は可能だが、権限 UX・常駐・透過窓の検証コストが「早く出す」に反する |
| 3 | Linux | 見送り | PulseAudio/PipeWire で技術的には可能だが、ディストリ差分の検証コストが高い。移植 PR は歓迎と README に書くに留める |

マイク権限・使用中インジケータ・sandbox 強制はいずれも OS 固有の作法であり、
プライバシー設計（§7）を「macOS の仕組みで証明する」構成にするため、v1 は macOS 特化が合理的。

---

## 4. 技術選定

### 比較

| 候補 | バイナリ/メモリ | 音声入力と権限 UX | 透過・クリックスルー | 判定 |
|---|---|---|---|---|
| **Swift + AppKit + AVAudioEngine（採用）** | 数 MB / ~30MB | 公式 API 直叩き。`AVCaptureDevice.requestAccess` で権限を正確に制御。entitlement も最小 | `NSWindow.ignoresMouseEvents` で公式サポート（cursorpets で検証済みの方式） | ✅ |
| Tauri v2 (Rust + WebView) | ~10MB / 30–50MB | cpal 等で可能だが権限プロンプト制御を自前実装 | 透明部だけのクリックスルーは未解決 FR（cursorpets 設計時に確認） | ❌ 過剰 |
| Electron | 80–150MB / 150–300MB | getUserMedia で楽だが、**マイクを扱うアプリに Chromium 同梱は監査面で最悪**（依存が巨大で「送信コードがない」ことを第三者が確認できない） | 既知トラブルあり | ❌ |

音声を扱う本アプリでは「監査可能性」が選定基準に加わる。ゼロ依存ネイティブなら、
監査対象は単一の小さなバイナリと Apple 標準 API のみになる。**Swift + AppKit ネイティブ一択。**

### 採用スタック

| 層 | 技術 | 理由 |
|---|---|---|
| 言語 | Swift 5.9+ | 標準。署名・notarization ツールチェーンと親和 |
| 音声入力 | `AVAudioEngine.inputNode.installTap` | 入力バッファを直接受け取れる標準 API。1 バス 1 タップで足りる |
| レベル計算 | Accelerate / vDSP（`vDSP_measqv` → RMS） | バッファ→1 float の縮約を SIMD で。tick あたりの CPU をほぼゼロに |
| 常駐/メニュー | `NSStatusItem` + `LSUIElement = YES` | Dock アイコンなしの純メニューバー常駐（cursorpets 同型） |
| ダック表示 | ボーダーレス `NSWindow` + `CALayer.contents` | cursorpets の小窓方式を流用。SpriteKit 不要 |
| アニメループ | `Timer`（状態別可変インターバル） | CADisplayLink は 60fps 前提で過剰 |
| 自動起動 | `SMAppService.mainApp`（macOS 13+） | Launch at Login を数行で |
| 設定保存 | `UserDefaults` | listening / corner / sensitivity / 初回済み の 4 キー程度 |
| 依存ライブラリ | なし | ゼロ依存を監査可能性の担保として売りにする |

### 重要 API・権限の調査結果

- **入力タップと RMS**: `inputNode.installTap(onBus: 0, bufferSize: N, format: nil)` で `AVAudioPCMBuffer` を受け取り、
  `vDSP_measqv`（平均二乗）→ 平方根で RMS、`20 * log10(rms)` で dBFS 化するのが定石。
  bufferSize は要求値であり OS が裁量で変えるため、**VAD は時間ベース判定にしてバッファサイズ非依存にする**（§5）。
- **権限フロー**: `Info.plist` に `NSMicrophoneUsageDescription` が必須（ないと即クラッシュ）。
  実行時は `AVCaptureDevice.authorizationStatus(for: .audio)` で確認し、`requestAccess(for: .audio)` で TCC ダイアログを出す。
  **App Sandbox を `com.apple.security.app-sandbox = true` で有効化したうえで、audio-input entitlement がないと権限プロンプト自体が出ない**ため、entitlement 設定が最優先の検証項目。
- **entitlement**: App Sandbox の有効化キーは `com.apple.security.app-sandbox`。マイク入力の追加 capability は
  `com.apple.security.device.audio-input`（Xcode の "Audio Input"）。
  Hardened Runtime 側も同キーで宣言する。旧 `com.apple.security.device.microphone` との要否関係は資料間で記述が揺れており、
  spike（Issue #1）で実機確定する。**network 系 entitlement は一切付与しない**（§7.5）。
- **Voice Processing（`setVoiceProcessingEnabled`）は v1 では使わない**: エコーキャンセル・ノイズ抑制が得られるが、
  他アプリ音声のダッキング等の副作用と検証コストが「音量を見るだけ」の要件に見合わない。
  定常ノイズ対策は適応ノイズフロア（§5）で行い、vDSP は RMS 計算のみに使う。
- **オレンジインジケータ**: macOS 12+ では、マイクを開いている間メニューバー（Control Center 脇）に
  オレンジの点が常時表示され、Control Center を開くと使用中アプリ名（duck）が表示される。
  **アプリ側から消す手段はなく、消すべきでもない。** これを逆手に取る設計判断は §7.3。

---

## 5. アーキテクチャ

主要コンポーネントは 5 つ。1 プロセスで完結し、音声はプロセスの外に出ない。

```
┌──────────────────────────────────────────────────────────────┐
│ DuckApp (NSApplicationDelegate, LSUIElement)                 │
│                                                              │
│  ┌───────────────┐ Listening on/off  ┌─────────────────────┐ │
│  │ StatusBar      │─────────────────▶│ AudioLevelSource     │ │
│  │ Controller     │ sensitivity/     │ (AVAudioEngine        │ │
│  │ (NSStatusItem) │ corner 設定      │  installTap)          │ │
│  └───────────────┘                  │ buffer → RMS → 即破棄 │ │
│                                     └──────────┬───────────┘ │
│                                     RMS 1 float │ (音声はここで消滅)
│                                     ┌──────────▼───────────┐ │
│                                     │ VADEngine             │ │
│                                     │ ・適応ノイズフロア      │ │
│                                     │ ・閾値 + attack        │ │
│                                     │ ・hangover             │ │
│                                     └──────────┬───────────┘ │
│                          SpeechEvent (enum のみ) │             │
│  ┌───────────────┐                  ┌──────────▼───────────┐ │
│  │ SpriteSheet    │◀── frame 番号 ───│ DuckOverlay           │ │
│  │ (CGImage       │                  │ ・演出状態機械         │ │
│  │  キャッシュ)    │                  │ ・borderless NSWindow │ │
│  └───────────────┘                  │  + CALayer / 四隅配置  │ │
│                                     └──────────────────────┘ │
└──────────────────────────────────────────────────────────────┘
```

### 境界の設計（最重要の設計判断）

keycat の「KeySource → 演出層は引数なし通知のみ」と同じ思想を音声に適用し、**二段の非可逆な縮約**で境界を切る：

1. **AudioLevelSource → VADEngine**: 渡るのは **RMS 音量 1 個の `Float` のみ**。
   `AVAudioPCMBuffer` は tap コールバックのスコープで寿命が終わり、保持・コピー・書き込みを一切しない。
   波形→1 float の縮約は非可逆であり、この境界を越えた時点で音声内容は物理的に存在しない。
2. **VADEngine → DuckOverlay**: 渡るのは `enum SpeechEvent { speechStarted / speechEnded(utteranceDuration) }` のみ。
   RMS すら演出層に出さない。仮に演出層にバグがあっても音量情報はそこにない。

tap コールバック（オーディオスレッド）は「vDSP で RMS 計算 → main queue へ dispatch → return」の最小仕事に限定する。

### VAD 状態機械（音量のみ、時間ベース）

```
              level > floor+offset が attack(250ms) 継続
   ┌─────────┐ ─────────────────────────────────────▶ ┌──────────┐
   │ Silence │                                        │ Speaking │
   └─────────┘ ◀───────────────────────────────────── └──────────┘
              level < floor+offset が hangover(1.2s) 継続
```

| パラメータ | 初期値（spike #1 で実測調整） | 根拠 |
|---|---|---|
| レベル | `20·log10(RMS)` dBFS、下限 -80 | 標準的な音量表現 |
| ノイズフロア | Silence 中のみ更新する EMA（時定数 ~10s）。Speaking 中は凍結 | ファン・空調・BGM 等の定常音に自動追従し、突発だけを拾う |
| 発話閾値 | floor + 9dB（Medium。High=+6 / Low=+12） | エネルギー VAD の一般的な相対閾値方式 |
| attack | 250ms 連続超過で speechStarted | タイピング音等の数十 ms のバーストを除外する |
| hangover | 1.2s 連続下回りで speechEnded | 息継ぎ・語間ポーズで発話が細切れにならない（VAD の定石） |

attack/hangover はフレーム数でなく壁時計時間で判定し、tap のバッファサイズ変動に依存しない。
speechStarted→speechEnded（hangover で接続された連続発話）を 1 utterance とし、duration を演出判定に使う。

### 演出状態機械（duck の相槌）

| 状態 | 遷移条件 | アニメ | tick 間隔 |
|---|---|---|---|
| `idle` | listening 中の無音 | まばたき（3–8s ランダム）+ ゆるい浮遊 | 500ms |
| `nodding` | speechStarted | うなずき 2 フレームのループ | 250ms |
| `tilt` | speechEnded 後 2.0s 無音継続 | 小首をかしげて静止（まばたき継続）。「続きを待つ」 | 500ms |
| `bigNod` | utterance ≥ 20s で speechEnded → 2.5s 無音 | 大きくうなずく 4 フレーム 1 回 →「なるほど」→ idle へ | 150ms |
| `sleep` | Listening off / マイク権限なし | 目を閉じて Zzz 2 フレーム | 1000ms |

- bigNod 条件を満たすときは tilt より優先する。tilt 中に speechStarted が来たら即 nodding へ。
- **listening 中は寝ない。** sleep は「マイクを開いていない」ことの視覚化専用とし、
  Control Center に duck が出ない状態と duck の就寝を常に同期させる（§7.3 の検証可能性の一部）。

### 処理フロー（1 バッファ）

1. tap コールバック（オーディオスレッド）: `vDSP_measqv` → RMS 計算。バッファ参照はここで終了（保存・コピーなし）
2. RMS 1 float を main queue へ dispatch
3. VADEngine: dBFS 化 → ノイズフロア更新（Silence 中のみ）→ 閾値比較 → attack/hangover 判定 → 遷移時に SpeechEvent 発行
4. DuckOverlay: SpeechEvent と内部タイマ（tilt 2.0s / bigNod 2.5s）で演出状態を更新
5. `CALayer.contents` に該当フレームの CGImage をセット（状態別 tick）

### ウィンドウと CPU 方針

- 窓設定は cursorpets と同一系: `.borderless` / `isOpaque = false` / `hasShadow = false` /
  `ignoresMouseEvents = true` / `level = .statusBar`（全画面アプリ上には出ない割り切り）/
  `collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]`
- 配置は四隅から選択（既定 Bottom Right）。基準画面は `NSScreen.main` ではなく、メニューバーを持つ primary screen
  （または `NSStatusItem` を開いた screen を明示的に保持したもの）に固定し、その `visibleFrame` + 16pt オフセットで Dock とメニューバーを避ける。移動しないので tick 内の窓操作はゼロ
- 音声処理は RMS 計算（vDSP）のみで ~10–20 回/秒。目標: listening 中 CPU < 1%、Listening off で 0%
- スプライトは起動時に全フレーム CGImage 化してキャッシュ。目標 RSS 30MB 以下

---

## 6. UI/UX

### メニューバー UI（設定ウィンドウなし）

```
🦆 (NSStatusItem。listening 中は塗りアイコン、off はアウトライン)
├─ ✓ Listening              ← 核。off = AVAudioEngine 停止 = マイク完全解放
├─   Nod once               ← 手動プレビュー（権限なしのデモモードでも動く）
├─ ─────────────
├─ Position     ▸ Bottom Right / Bottom Left / Top Right / Top Left
├─ Sensitivity  ▸ Low / Medium / High
├─ ─────────────
├─ Launch at Login  [ ]
├─ Privacy & About…         ← §7 の要約 + GitHub リンク + バージョン
└─ Quit
```

### 設定項目（v1）

| 項目 | 値 | 既定 |
|---|---|---|
| Listening | on/off | 前回状態を復元（初回はオンボーディングで明示開始） |
| Position | 四隅 | Bottom Right |
| Sensitivity | Low / Medium / High | Medium |
| Launch at Login | on/off | off |

### 初回起動体験

1. 起動 → オンボーディングウィンドウ表示：duck の 10 秒説明（デモアニメ再生）+
   **プライバシー要約（§7.1 の表: 見るのは音量 1 個だけ）** + [Start listening] ボタン
2. ボタン → `AVCaptureDevice.requestAccess(for: .audio)` → TCC ダイアログ
3. 許可 → duck が選択した隅に登場して挨拶の nod。同時に
   「メニューバーのオレンジの点はマイク使用中の印です。Listening を切ると Control Center から duck が消えます」と
   1 文表示（チュートリアルはこれで終わり）
4. 拒否 → duck は **sleep 姿で登場（デモモード）**。Nod once で演出だけ楽しめる。
   メニューバーアイコンに ⚠ を付け、「マイクが未許可です → 設定を開く」からシステム設定の
   マイクペインへディープリンク。起動のたびにモーダルで迫らない（keycat 方式）

### エッジケースの割り切り（v1）

- **BGM・環境音**: 適応ノイズフロアが持ち上がり定常音では nod しないが、音楽のダイナミクスに時々うなずくことは残る。
  README の FAQ で「duck はいい曲にもうなずくことがある」と正直に書き、Sensitivity Low を案内する
- **タイピング音**: attack 250ms で大半を除外。メカニカルキーボードの高速連打は誤反応しうる → Sensitivity で調整
- **通話相手の声（スピーカー出力）を拾う**: nod が増えるだけ。内容は原理的に知り得ないため実害なし（§7.7）
- 全画面アプリの上には出ない（`.statusBar` レベルの仕様として許容）
- スクリーンショット・画面共有には写る（聞き役がいる絵になるのでむしろネタ。README に明記）

---

## 7. プライバシー設計（最重要）

マイクを常時開くアプリは、キーロガーと同じく「信頼が製品価値そのもの」である。
keycat の Input Monitoring 設計と同じ厳密さで、**「作者を信じてください」ではなく「OS と構造が禁じています」**を主張できる形にする。

### 7.1 原則：「何を聞いて、何を聞かないか」

| | 内容 |
|---|---|
| **見るもの** | 各オーディオバッファの **RMS 音量 1 個の float** のみ |
| **見ないもの** | 波形の保存・コピー、内容を復元しうる特徴量（スペクトログラム・MFCC・ピッチ系列）、音声認識（STT）、話者識別、他アプリの system audio への直接アクセス |
| **注意する境界** | duck は system audio を tap しないが、スピーカーからマイクに物理的に入った Zoom / Meet / BGM 等の音の **loudness** は処理し得る（§7.7） |
| **残すもの** | 何も残さない。音声由来のデータはファイル・ログ・永続メモリのいずれにも書かない |
| **送るもの** | 何も送らない。ネットワークコードが存在せず、network entitlement もない（OS が強制） |

### 7.2 多層設計

1. **層 1 — バッファの寿命**: `installTap` のバッファは tap コールバック内で RMS 計算に使われた直後にスコープアウトする。
   retain・コピー・`AVAudioFile` 書き出しをしない。録音 API（`AVAudioRecorder`）はリポジトリに存在しない。
2. **層 2 — 非可逆縮約**: コールバックの出力は RMS 1 float。波形→音量への縮約は不可逆で、
   この境界の先に音声内容は物理的に存在しない。周波数分析・特徴量抽出のコードを持たない
   （spike の結果、人声帯域のエネルギー比 1 値が必要になった場合も「帯域別の音量」までとし、系列・スペクトルは扱わない。採用時は本節を改訂する）。
3. **層 3 — イベント境界**: VADEngine → 演出層は `SpeechEvent` enum のみ。RMS 値すら UI・演出・ログに出さない。
4. **層 4 — 禁止 API の CI ガード**: `SFSpeechRecognizer` / `AVAudioFile` / `AVAudioRecorder` / `AVCaptureAudioFileOutput` /
   `URLSession` / `Network.framework` / `NWConnection` / `socket(` などを source / build / entitlement / workflow files から検出したら
   CI を fail させる（privacy-guard）。`docs/` と参考資料は allowlist に置き、禁止 API 名を説明する文書で CI が落ちないようにする。
   「実装に含まれていないこと」をバッジで常時証明する。

### 7.3 マイク使用インジケータ（オレンジの点）への態度 — duck 固有の最重要判断

macOS はマイクを開いている間、メニューバーにオレンジの点を表示し続け、Control Center に「duck」と使用者名を出す。
「常駐アプリの点けっぱなしのオレンジドット」は一般ユーザーが最も不審に思う挙動であり、消したがる声も多い。
duck はこれを隠すのではなく**監査 UI として採用する**：

- **消せない・消さない。** README とオンボーディングで「オレンジドット＝macOS 全体でマイク使用中、
  Control Center に duck が出ている＝duck がマイク使用中」と最初に説明する
- **Listening off は 1 クリック**（メニューバー直下の最上段）。off は `AVAudioEngine.stop()` + tap 除去による
  **duck によるマイクの完全解放**であり、ミュートやフラグではない。→ Control Center のマイク使用欄から duck が消える
- duck の sleep アニメと「Control Center に duck が出ない状態」を常に同期させる。ユーザーは
  「duck が寝ている ⇔ Control Center に duck がいない ⇔ duck はマイクを使っていない」を自分の目で照合できる。
  オレンジドット自体は macOS 全体のマイク使用表示なので、Zoom / Meet など他アプリがマイクを使っている間は残る。
  duck が唯一のマイク使用者だった場合だけ、Listening off と同時にオレンジドットも消える。
  **アプリが偽装できない OS のインジケータを、duck の主張の検証手段として案内する**（README に手順として明記）
- Control Center のマイク使用欄に duck が出ることも「確認方法」として README に載せる
- 「点きっぱなしが気になる」への現実解は自動化ではなく 1 クリック off。無音自動 off は v2 検討（§2）

### 7.4 ログ方針

- RMS 値・レベル値・VAD 判定値を**成功パスでログに出さない**。デバッグビルドでも「speechStarted」等の遷移事実まで
- 診断ログは権限状態・エンジンの生死・状態遷移のみ。`os_log` は static 文字列
- クラッシュレポート送信機構（Sentry 等）は組み込まない

### 7.5 ネットワーク不使用の保証（keycat 方式）

- コードベースに URLSession / Network.framework / ソケット API を含めない。依存ゼロ方針（§4）はこの検証を単純にするため
- **App Sandbox を `com.apple.security.app-sandbox = true` で有効化し、追加 capability は
  `com.apple.security.device.audio-input` のみにする**。
  `com.apple.security.network.client` / `.server` を付与しない。sandbox 下では entitlement のない
  outbound 接続を OS が拒否する。→「マイクの音が外に出ない」ことを OS が強制する
- 自動更新を入れない（§2）のも同じ理由。更新は GitHub Releases / Homebrew に委ねる

### 7.6 検証可能性

- **コード側**: 音声バッファに触るコードを `Sources/AudioLevelSource.swift` の**単一ファイル・100 行以下**に隔離する。
  第三者はこのファイルだけ読めば監査が完了する。tap コールバック該当行に `// PRIVACY:` アンカーを置き、README から行パーマリンクで参照
- **CI 側**: §7.2 層 4 の privacy-guard ワークフロー。バッジを README 上部に置く
- **バイナリ側**: `codesign -d --entitlements - /Applications/duck.app` で network entitlement がないことを
  ユーザー自身が確認する手順を README に載せる
- **OS 側**: §7.3 の Control Center 照合手順。duck が唯一のマイク使用者である場合はオレンジドット消灯も確認する

### 7.7 マイク共有と会議

macOS のマイクは排他ではなく複数アプリで共有できるため、会議中も duck は動作しうる。
このとき duck は Zoom / Meet の system audio を直接読むわけではないが、スピーカーからマイクに物理的に入った通話相手の声や BGM の loudness は処理し得る。
受け取り得るのは音量 1 値のみであり、内容・話者は原理的に知り得ない。
README にこの事実を隠さず書く（「会議中は邪魔なら off に。duck は誰の発言かも、何を言ったかも知らない」）。
会議アプリとの同時使用の実機挙動は P2 検証（§10）。

---

## 8. 配布方法

| 項目 | v1 の方針 | 理由 |
|---|---|---|
| 一次配布 | GitHub Releases に Universal 2 の `.zip`（.app 同梱） | tag push → 自動リリース。dmg 化の手間は後回し |
| Homebrew | 自前 tap: `brew install --cask Saber5656/tap/duck` | README の 1 行インストール。本家 cask は知名度要件があるためまず tap |
| 署名 | **Developer ID Application 証明書（必須扱い）** | TCC はコード署名の同一性でアプリを識別する。ad-hoc 署名は更新のたびに**マイク権限が剥がれる**ため、マイク前提の duck では成立しない（keycat §9 と同じ結論） |
| Notarization | `notarytool` + staple を GitHub Actions に組み込み | Gatekeeper 警告ゼロは「マイクを預けてもらう」ための最低条件 |
| App Store | 出さない | sandbox 化はプライバシーのために行うが、MAS 審査コストは回避 |
| 自動更新 | なし。About に「Check for Updates (GitHub)」リンクのみ | ネットワーク不使用の主張を保つ（§7.5） |
| CI | build → privacy-guard grep → codesign → notarize → staple → Release 添付 | 検証と配布を同一ワークフローで |

トラブルシューティングとして `tccutil reset Microphone <bundle-id>` を README に記載する。

---

## 9. README 構成案（英語）

```markdown
<バナー画像: 画面隅のアヒルがコードを聞いている横長イラスト PNG>

# duck 🦆
> A rubber-duck debugging companion that listens and responds with
> gentle backchannels. It hears you — but never understands you.

<デモ GIF: ターミナル脇の duck に話しかける→うなずく→黙る→小首をかしげる→
 長い説明の後に大きくうなずく、の 10 秒ループ>

## Install
    brew install --cask Saber5656/tap/duck
Or grab the notarized .app from Releases. macOS 13+.

## What it does
- Sits in a corner of your desktop and listens while you explain your bug out loud
- Nods while you talk, tilts its head when you pause, gives a big "mm-hm!"
  after a long explanation
- No AI. No speech recognition. No answers. You solve the bug —
  the duck just gets you to say it out loud.

## 🔒 Privacy — read this first
duck opens your microphone, so here is exactly what it does with it:
  | duck sees                                      | duck never does                      |
  |------------------------------------------------|--------------------------------------|
  | the loudness of each microphone buffer (one number), including sounds physically captured by the mic | speech-to-text / recording / storing |
  | —                                              | direct system-audio capture from other apps |
  | —                                              | writing audio-derived data anywhere  |
  | —                                              | any network access — no networking code and **no network entitlement (OS-enforced by App Sandbox)** |
- All microphone code lives in one file: [`AudioLevelSource.swift`](permalink)
  (< 100 lines — audit it yourself). Buffers are reduced to one number and dropped.
- **The macOS orange mic dot stays on while duck listens. That's honesty, not a bug.**
  Toggle "Listening" off in the menu bar and Control Center should stop listing
  duck, because duck fully releases the microphone. If no other app is using the
  mic, the orange dot goes out too. The OS indicator is your independent proof.
- CI fails if any speech/recording/networking symbol appears: privacy-guard workflow
- Verify the shipped binary yourself:
      codesign -d --entitlements - /Applications/duck.app

## Why a duck that can't understand you?
Rubber-duck debugging works because *you* do the explaining. An assistant that
answers back defeats the exercise. duck is deliberately incapable of
understanding — it just rewards you for talking.

## Controls
(メニュー項目の表: Listening / Nod once / Position / Sensitivity / Launch at Login / Quit)

## FAQ
- "It nodded at my music" — yes, duck vibes to good beats sometimes. Lower the sensitivity.
- 会議との共存、全画面で見えない、権限リセット (tccutil) など

## License
MIT. Sprites are original work, CC0.
```

バッジは license / release / **privacy-guard** の 3 つ。
デモ GIF とインストールコマンドがファーストビュー、Privacy 節がその直下に来ることを必須とする。

---

## 10. リスクと実装前検証項目

| 優先度 | 項目 | 内容 / 検証方法 |
|---|---|---|
| **P0** | sandbox + audio-input entitlement での AVAudioEngine 動作一式 | entitlement（`app-sandbox` / `audio-input` / 旧 microphone キーの要否）→ TCC プロンプト表示 → 許可 → tap で RMS 取得 → stop で Control Center から duck が消えること（duck 単独使用時はオレンジドット消灯も）を実機確認。ここが崩れると §7 の根幹（sandbox 有効）が崩れる → spike #1 |
| **P0** | 音量のみ VAD の成立性 | 実発話・タイピング・BGM・ファン音で、誤 nod と取りこぼしが許容内に収まる attack/hangover/floor/閾値の組が見つかるか。人声帯域エネルギー比を足す fallback の要否もここで判断 → spike #1 |
| P1 | デバイス切替・構成変更への追従 | AirPods 着脱、入力デバイス変更、サンプルレート変更時に engine が落ちず復帰するか（`AVAudioEngineConfigurationChange` 通知 → 再構成）。手動テスト表を作る |
| P1 | 署名・notarization と TCC 同一性 | Developer ID 加入、CI からの notarytool、更新後にマイク権限が維持されることをクリーン環境で確認 |
| P1 | スプライトの権利 | 完全自作（CC0）。既存キャラクター（他社のアヒル IP）と混同されないデザインにする。素材完成時にレビュー |
| P2 | 会議アプリとの同時使用 | Zoom / Meet がマイク使用中でも duck が入力を受けられるか（macOS のマイクは共有可能なはず）。両立しない環境を洗い出し README に書く |
| P2 | 常駐時の電力影響 | 1 時間 listening での Energy Impact を Instruments で計測。README に実測値を書けると理想 |
| P2 | スリープ復帰・Space 切替時の窓と engine | 復帰後に窓が消える/engine が止まる事象への保険（orderFrontRegardless / engine 再起動） |
| P3 | 名称の一般性 | "duck" は一般語（Cyberduck、DuckDuckGo 等と無関係であることが分かる説明文に）。リリース前に表記を確認 |

**最重要リスク**: P0 の 2 件。特に「音量のみで相槌として自然な検出ができるか」は製品の成立条件そのもの。
方式変更（帯域エネルギー追加）の判断材料まで含めて、本実装前に捨てられるプロトタイプで必ず確認する（Issue #1）。

---

## 11. v1 Issue 分割案（9 個）

- **#1 `Spike: volume-only VAD with AVAudioEngine in a sandboxed app`** — ラベル: `spike`, `design`
  `app-sandbox` + audio-input entitlement + network entitlement なしの最小アプリで、TCC プロンプト → installTap → vDSP RMS → speaking/silence 判定のコンソール出力までを捨てプロトで作り、P0 リスク 2 件を検証する。実発話・タイピング・BGM で attack/hangover/閾値の初期値を決め、entitlement の要否（app-sandbox / audio-input / microphone）と stop 時に Control Center から duck が消えることを確認する。
  受け入れ条件: 許可フロー一式が動き、通常発話が speaking、タイピング・無音が silence と判定される。決定パラメータと計測メモを Issue コメントに記録。

- **#2 `Set up menu bar app skeleton with sandbox and privacy-guard CI`** — ラベル: `infra`
  `LSUIElement` の Swift アプリ雛形、NSStatusItem メニュー（Listening トグル仮 / Quit / Launch at Login）、App Sandbox 有効・network entitlement なし、UserDefaults 永続化、GitHub Actions の build + source / build / entitlement / workflow files を対象にした禁止シンボル grep（privacy-guard）を整備する。
  受け入れ条件: Dock 非表示で常駐し、メニューが機能し、設定が再起動後も保持され、privacy-guard が green。

- **#3 `Implement AudioLevelSource with discard-only RMS tap`** — ラベル: `enhancement`
  AVAudioEngine と installTap を単一ファイル（~100 行、`// PRIVACY:` アンカー付き）に隔離し、バッファ→RMS→即破棄、start/stop によるマイク完全解放、`AVAudioEngineConfigurationChange` への追従を実装する。出力は RMS float の callback のみ。
  受け入れ条件: start で RMS が流れ stop で Control Center から duck が消える（duck が唯一のマイク使用者ならオレンジドットも消灯する）。バッファ参照がコールバック外に出ないことをレビューで確認。AirPods 着脱で動作継続。

- **#4 `Implement VAD engine with threshold, hangover, and adaptive noise floor`** — ラベル: `enhancement`
  時間ベースの attack（250ms）/hangover（1.2s）、Silence 中のみ更新する EMA ノイズフロア、Sensitivity 3 段、`SpeechEvent`（speechStarted / speechEnded(duration)）の発行を実装する。合成 RMS 系列によるユニットテストを含む。
  受け入れ条件: §5 の遷移表どおりに動き、attack 未満のバーストと hangover 内の息継ぎが無視されることがテストで示される。

- **#5 `Create duck spritesheet (idle, nod, tilt, big-nod, sleep)`** — ラベル: `assets`, `design`
  32px グリッド（@2x）のアヒルスプライトを自作する。idle/blink、nodding ループ、tilt、bigNod、sleep の全フレームと、状態→フレームのマッピング `duck.json`（cursorpets の pet.json 形式踏襲）を定義する。ライセンス（CC0）を LICENSE-assets に明記。
  受け入れ条件: 全状態のフレームが揃い、第三者素材を含まず、ライセンス表記が完備。

- **#6 `Build corner overlay window with reaction state machine`** — ラベル: `enhancement`
  ボーダーレス・クリックスルー・全 Space 表示の小窓を四隅配置（visibleFrame 基準）で実装し、CALayer スプライト描画、idle→nodding→tilt→bigNod→sleep の演出状態機械（状態別 tick）、SpeechEvent との結線、手動トリガ（Nod once）を実装する。
  受け入れ条件: 話すと nod、2 秒沈黙で tilt、20 秒以上話した後の沈黙で bigNod、Listening off で sleep になり、アニメ中 CPU < 2%。

- **#7 `Add onboarding and permission flow with sleeping demo mode`** — ラベル: `ux`
  初回起動ウィンドウ（10 秒説明 + プライバシー要約 + Start listening）、`AVCaptureDevice.requestAccess`、拒否時の sleeping デモモード（Nod once 可・⚠ バッジ・設定ディープリンク）、Control Center で duck のマイク使用を確認する 1 文説明、Listening 状態の復元を実装する。
  受け入れ条件: 未許可でもクラッシュ・モーダル連発なしで sleep 常駐し、許可後は再起動不要で listening が始まり、プライバシー要約が表示される。

- **#8 `Set up signed and notarized release pipeline with Homebrew tap`** — ラベル: `infra`
  GitHub Actions で tag push 時に Universal 2 ビルド → codesign（Developer ID）→ notarytool → staple → Releases に zip 添付。`Saber5656/homebrew-tap` に cask を追加する。
  受け入れ条件: クリーン環境で `brew install --cask` から警告なしで起動し、アップデート後もマイク権限が維持される。

- **#9 `Write README with privacy-first section, banner, and demo GIF`** — ラベル: `docs`
  §9 の構成で英語 README を作成する。バナー、デモ GIF（10 秒ループ）、1 行インストール、Privacy 表・`AudioLevelSource.swift` パーマリンク・オレンジドットの説明・codesign 検証手順、FAQ を含める。
  受け入れ条件: デモ GIF とインストールが first view に収まり、Privacy 節がその直下にあり、バッジ 3 個（license / release / privacy-guard）と全リンクが有効。

推奨着手順: #1 → (#2, #5 並行) → #3 → #4 → #6 → #7 → (#8, #9 並行)。

---

## 参考資料（WebSearch 検証済み）

- AVAudioEngine の入力タップと RMS/dB 計測（installTap、vDSP、20·log10 変換、1 バス 1 タップ）:
  [Kodeco: AVAudioEngine Tutorial](https://www.kodeco.com/21672160-avaudioengine-tutorial-for-ios-getting-started/page/2),
  [How to Get Sound Level in iOS Using Swift (Medium)](https://medium.com/@garejakirit/how-to-get-sound-level-in-ios-using-swift-c71072dd3414)
- マイク権限と sandbox entitlement（`app-sandbox` で App Sandbox を有効化し、マイク入力には audio-input capability を付与する）:
  [Apple: com.apple.security.device.audio-input](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.device.audio-input),
  [Apple: Enabling App Sandbox（entitlement 一覧）](https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/EnablingAppSandbox.html),
  [Flutter: Building macOS apps（sandbox + hardened runtime のマイク設定例）](https://docs.flutter.dev/platform-integration/macos/building)
- エネルギーベース VAD の定石（10–30ms フレームのエネルギー閾値、適応閾値、hangover による末尾保持）:
  [Aalto University: Voice activity detection](https://speechprocessingbook.aalto.fi/Recognition/Voice_activity_detection.html),
  [Deepgram: Voice Activity Detection Overview](https://deepgram.com/learn/voice-activity-detection),
  [kunaljathal/VAD（シンプルなエネルギー VAD 実装例）](https://github.com/kunaljathal/VAD)
- macOS のマイク使用インジケータ（macOS 12+ で常時表示、Control Center に使用アプリ名、アプリからは消せない、気にするユーザーが多い）:
  [Apple Support: Hide privacy indicators on external displays](https://support.apple.com/en-us/118449),
  [Apple Support: Use Control Centre on Mac](https://support.apple.com/en-euro/guide/mac-help/mchl50f94f8f/mac),
  [macReports: Mic/Camera indicator in the menu bar](https://macreports.com/microphone-or-camera-icon-orange-or-green-dot-stuck-in-the-menu-bar-on-mac/),
  [CDM: the macOS Orange Dot（配信・音楽ユーザーの反応）](https://cdm.link/fix-the-orange-dot/)
- rubber duck debugging と既存プロダクト:
  [Wikipedia: Rubber duck debugging](https://en.wikipedia.org/wiki/Rubber_duck_debugging),
  [rubberduckdebugging.com](https://rubberduckdebugging.com/),
  [Quack The Code (Devpost)](https://devpost.com/software/quack-the-code),
  [rdd — rubber duck debugging (Google Play)](https://play.google.com/store/apps/details?id=io.github.gongboo.rdd&hl=en)

---

## Changelog

- 2026-07-05: 初版
