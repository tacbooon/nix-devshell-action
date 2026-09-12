# Nix DevShell Action

Nix devShell 環境を GitHub Actions のステップに読み込みます。

Languages: [English](README.md)

## 前提条件

- Nix がインストールされており、Flakes が有効化されていることが必要です。
- `openssl` が利用可能であることが必要です。GitHub ホステッドランナーにはデフォルトで含まれています。

## 基本的な使い方

このアクションは指定された flake に対して `nix print-dev-env` を実行し、devShell 環境を構築する bash スクリプトを生成します。そして、そのスクリプトが追加・変更する変数を抽出し、安全のためにフィルタリングした変数を `$GITHUB_ENV` と `$GITHUB_PATH` に書き込みます。これにより後続のステップで devShell 相当の環境を利用できます。

従来は各ステップの先頭に `nix develop -c` を置く必要がありました。

```yaml
- uses: cachix/install-nix-action@v31
- run: nix develop -c -- pytest
- run: nix develop -c -- ruff check .
```

事前にこのアクションを実行すれば、後のステップでは素のコマンドのままで devShell 内と同じコマンドや環境変数を使用できます。

```yaml
- uses: cachix/install-nix-action@v31
- uses: tacbooon/nix-devshell-action@v1
- run: pytest
- run: ruff check .
```

## 入力

### flake

パス、URI または flake リファレンス (installable) です。デフォルトではカレントディレクトリ (`.`) を使用します。

```yaml
- uses: tacbooon/nix-devshell-action@v1
  with:
    flake: ./subdir
```

```yaml
- uses: tacbooon/nix-devshell-action@v1
  with:
    flake: github:owner/repo
```

```yaml
- uses: tacbooon/nix-devshell-action@v1
  with:
    flake: .#ci
```

### export-path

`GITHUB_PATH` に書き込むパスのフィルタリングに使用する glob パターンです。複数パターンを指定する場合は改行で区切ります。

このアクションは devShell が `PATH` に追加するパスを全て `GITHUB_PATH` に書き込むことはしません。代わりに `export-path` オプションに与えられたパターンのいずれか 1 つ以上にマッチしたパスだけを `GITHUB_PATH` に書き込みます。デフォルトでは `/nix/store/*` と `$GITHUB_WORKSPACE/*` にマッチするパスだけを `GITHUB_PATH` に書き込みます。

以下の例ではデフォルトパターンに加えて `/path/to/bin/*` を `export-path` に追加します。このオプションの指定はデフォルトパターンを上書きします。カスタムパターンに加えてデフォルトパターンを維持したい場合は明示的に指定が必要です。

```yaml
- uses: tacbooon/nix-devshell-action@v1
  with:
    export-path: |
      /nix/store/*
      /path/to/bin/*
      $GITHUB_WORKSPACE/*
```

例えば、devShell が `/path/to/bin/dir` と `/path/to/other/dir` を `PATH` に追加すると仮定します。`/path/to/bin/*` にマッチする `/path/to/bin/dir` は `GITHUB_PATH` に書き込まれて後段のステップで利用できます。しかし、`/path/to/other/dir` はマッチするパターンが存在しないため `GITHUB_PATH` に書き込まれません。

なお、このオプションが展開できる環境変数は `GITHUB_WORKSPACE` と `PWD` だけです。

### export-env

`GITHUB_ENV` に書き込む環境変数のフィルタリングに使用する glob パターンのリストです。複数パターンを指定する場合は改行で区切ります。

このアクションはデフォルトでは `GITHUB_ENV` に何も書き込みません。環境変数を出力するには `export-env` オプションに出力対象となる変数名にマッチするパターンを追加してください。以下では `APP_*` と `DB_*` にマッチする環境変数だけを `GITHUB_ENV` に書き込みます。

```yaml
- uses: tacbooon/nix-devshell-action@v1
  with:
    export-env: |
      APP_*
      DB_*
```

例えば、devShell が環境変数 `APP_NAME` と `MYAPP_URL` を定義すると仮定します。`APP_*` にマッチする `APP_NAME` は `GITHUB_ENV` に書き込まれて後続のステップで参照できます。しかし、`MYAPP_URL` はマッチするパターンが存在しないため `GITHUB_ENV` に書き込まれません。

例外として `_` `ACTIONS_*` `BASHOPTS` `BASH_ENV` `CI` `ENV` `EUID` `GITHUB_*` `IFS` `OLDPWD` `PATH` `PPID` `PWD` `RUNNER_*` `SHELLOPTS` `SHLVL` `UID` についてはパターンにマッチしても `GITHUB_ENV` に書き込まれることはありません。

## 思想

このアクションがデフォルトで全てのパスと環境変数を出力しないのは後段のステップへの予期しない副作用を避けるためです。devShell 環境はあなたが明示的に定義した変数以外にも非常に多くの変数を書き換えます。これを全て暗黙的に後段のステップに引き継ぐべきではありません。あなたが作成するステップはもちろん、GitHub で配布される多くのアクションもこれに対応できません。

また、このアクションは内部で `nix develop` を実行せず `nix print-dev-env` を利用します。これにより、`nix develop` が暗黙的に行う `bash-interactive` のダウンロードやビルドを回避し、ステップごとのシェル起動オーバーヘッドのない高速な実行を実現しています。

## セキュリティ

このアクションは `nix print-dev-env` が生成するスクリプトを `source` して読み込みます。このスクリプトには devShell の `shellHook` が含まれるため、指定した flake の任意のコードがワークフロー内で実行されます。`flake` には信頼できるソースのみを指定してください。信頼できない flake を指定すると、ワークフローの権限で任意のコードが実行される可能性があります。

## 開発

コントリビュータは `nix develop` を使用して開発環境を構築できます。ツールの一覧については `flake.nix` を参照してください。

## ライセンス

このソフトウェアは MIT ライセンスのもとで提供されます。詳細については [LICENSE](LICENSE) を参照してください。
