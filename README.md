# Insônia ☕

App de menu bar pra macOS que **impede o Mac de dormir / a tela de apagar** por um tempo definido — sem mensalidade, sem App Store. Feito em Swift nativo, usa as *IOKit power assertions* (a mesma API que o `caffeinate` do sistema usa).

> Requer **macOS 13 ou mais novo**. Universal (Apple Silicon + Intel).

## O que faz

- **Durações**: sem limite, 15 min, 30 min, 1 h, 2 h.
- **Até hora X**: até 17/18/19/20/22h ou meia-noite.
- **Dois modos**:
  - *Manter a tela ligada* → pra apresentar (a tela não apaga).
  - *Manter só o sistema* → pra rodar um modelo de madrugada (a tela **pode** apagar e poupar energia, mas o Mac não dorme).
- **Atalhos**: Reunião (1h, tela), Apresentação (sem limite, tela), Modelo rodando (sem limite, só sistema).
- Contagem regressiva no menu bar, aviso quando está na **bateria**, bipe no fim e **Abrir no login**.

---

## 📥 Instalar (pros amigos — sem compilar nada)

1. Baixe o **`Insonia.zip`** na aba **[Releases](../../releases)**.
2. Dê **duplo clique** pra descompactar → vai virar **`Insônia.app`**.
3. Arraste o `Insônia.app` pra pasta **Aplicativos**.
4. Na **primeira vez**, o macOS vai bloquear dizendo que *"não foi possível verificar o desenvolvedor"*. Isso é normal — o app não é pago/assinado pela Apple, mas é seguro. Pra liberar (uma vez só):
   - Tente abrir o app (vai dar o aviso → clique em **OK/Concluído**).
   - Vá em **Ajustes do Sistema › Privacidade e Segurança**, role até o fim e clique em **"Abrir Assim Mesmo"** ao lado de *Insônia*.
   - Abra de novo e confirme. Pronto — nas próximas vezes abre direto.

**Atalho pra quem curte Terminal** (faz tudo de uma vez, sem o aviso):
```bash
xattr -dr com.apple.quarantine "/Applications/Insônia.app" && open "/Applications/Insônia.app"
```

> Por que esse perrengue e no Windows um `.exe` só roda? Porque a Apple cobra US$99/ano pra "notarizar" apps e tirar esse aviso. Como isto é de graça, fica essa aprovação única. Depois é igualzinho a qualquer app.

---

## 🛠 Compilar do zero (só você, dev)

Precisa apenas do Swift (vem com as *Command Line Tools*: `xcode-select --install`). Não precisa do Xcode nem de conta paga.

```bash
./build.sh          # gera Insônia.app + Insonia.zip (universal)
open "Insônia.app"  # testa na hora (ícone ☕ aparece na barra de menu)
```

## 🚀 Publicar uma nova versão no GitHub

Tem um workflow do **GitHub Actions** (`.github/workflows/release.yml`) que faz tudo sozinho: é só criar uma tag e dar push.

```bash
git tag v1.0.0
git push origin v1.0.0
```

O Actions compila o app universal num Mac da nuvem, empacota e cria a **Release** com o `Insonia.zip` anexado. Seus amigos só clicam em baixar. (Os runners macOS do GitHub são gratuitos em repositório público.)

Prefere fazer na mão? `./build.sh` e depois:
```bash
gh release create v1.0.0 Insonia.zip --generate-notes
```

## Notas

- Fechar o app (**Sair**) ou ele crashar **solta a assertion na hora** — não tem como "travar acordado".
- **Abrir no login** funciona melhor com o app dentro de `/Applications`. Fora disso o macOS pode pedir aprovação manual (o app te avisa e abre os Ajustes).
- O app **não** decide nada sozinho: se você ativar "sem limite" na bateria, ele segura até você desligar (por isso o aviso "⚠︎ na bateria" no menu).
- Desligamento tem precisão de ~1 segundo (timer de 1s) — irrelevante pra um app de manter acordado.

## Estrutura

```
Package.swift                 — manifesto SwiftPM
Info.plist                    — vira o Contents/Info.plist do .app (LSUIElement = menu bar)
build.sh                      — compila universal, monta o .app e gera o .zip
.github/workflows/release.yml — publica a Release ao dar push numa tag vX.Y.Z
Sources/Insonia/
  main.swift                  — entrada (NSApplication, .accessory)
  AppDelegate.swift           — sobe o controller
  PowerManager.swift          — cria/solta a IOKit assertion + timer + wake
  StatusMenuController.swift   — ícone e menu do menu bar
```
