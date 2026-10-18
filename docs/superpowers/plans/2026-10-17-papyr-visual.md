# Papyr: identidade visual, ícone e splash. Plano de implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Trocar o visual padrão do Material pela direção "Papel e tinta" (cores da logo, Newsreader + Outfit). Isso inclui a barra só com ícones e o botão Escanear no meio, a câmera em tela cheia, Ajustes refeito, e ícone e splash em azul-marinho com a logo em vetor.

**Architecture:**
- O tema fica num arquivo só (`lib/theme.dart`): `ColorScheme` montado à mão e fontes variáveis dentro do APK.
- A marca é desenhada por um `CustomPainter` (`lib/widgets/papyr_mark.dart`).
- A barra (`SnakeBar`) passa a ter só os ícones laterais. O botão Escanear vai no slot `floatingActionButton` do Scaffold, com uma posição própria.
- Os recursos do Android (ícone adaptativo, splash do 12+ e do 11) são VectorDrawables gerados por `tool/brand.py` a partir da geometria do apêndice A da spec. Só o nome "Papyr" é PNG.

**Tech Stack:**
- Flutter 3.44.5 / Dart 3.12.2 (`/snap/bin/flutter`), Material 3 e `CustomPainter`;
- recursos Android XML (VectorDrawable, `animated-vector`, SplashScreen API 31+);
- Python 3 + Pillow 9.0.1 e `google-chrome --headless` só para o gerador.

**Spec:** `docs/superpowers/specs/2026-10-17-papyr-visual-design.md`, citada abaixo como "spec §N". O spec do app (`docs/superpowers/specs/2026-10-17-papyr-scanner-design.md`) continua valendo onde a spec visual não muda nada. Em caso de conflito, a spec visual vence.

## Global Constraints

- **Ambiente e dependências**
  - Flutter local `/snap/bin/flutter` 3.44.5. Não atualizar Flutter, Gradle nem AGP.
  - `dependencies`: só `camera: ^0.12.1`. Nenhum pacote novo, nem em `dev_dependencies` (sem `google_fonts`, `flutter_svg`, `flutter_launcher_icons` ou `flutter_native_splash`).
  - As fontes ficam em `assets/fonts/`, dentro do APK, sem download em tempo de execução e sem permissão `INTERNET`.
- **Cores e fontes**
  - Cores exatamente como na tabela da spec §5.1. **Nada de `ColorScheme.fromSeed`.**
  - Nas telas de mídia (câmera, editor e visualizadores), "papel" é `#F6F3EC` e "tinta" é `#102E50`, valores fixos nos dois temas.
  - O Newsreader sempre leva `fontVariations` com `FontVariation('opsz', <tamanho>)` e `FontVariation('wght', 500)`, e também `fontWeight: FontWeight.w500`.
- **Textos**
  - Em português, com a cópia exata da spec e das tasks. Rótulos de seção em frase normal, nunca em CAIXA ALTA.
  - Os nomes acessíveis atuais não mudam: `Tirar foto`, `Lanterna`, `Compartilhar`, `Excluir`, `Remover foto`.
  - Os novos são `Arquivos`, `Escanear`, `Ajustes` e `Fechar`.
- **Movimento:** só a pílula snake e o retorno de toque. Com `MediaQuery.disableAnimationsOf(context)`, a pílula pula direto.
- **Áreas de toque:** todo alvo tem pelo menos 48×48 dp (`androidTapTargetGuideline`).
- **Limites desta máquina (ela já travou):** um build Gradle por vez, com `nice -n 15`. Nada em paralelo com o emulador além do próprio teste.
- **Protocolo do emulador** (só nas tasks que pedem):
  - subir: `nice -n 15 ~/Android/Sdk/emulator/emulator -avd Medium_Phone_API_36.1 -cores 2 -memory 3072 -no-audio -no-snapshot-save >/dev/null 2>&1 &` e depois `adb wait-for-device shell 'while [ "$(getprop sys.boot_completed)" != 1 ]; do sleep 2; done'`;
  - screenshot: `adb exec-out screencap -p > /tmp/claude-1000/shot.png`, e depois olhar a imagem;
  - tema escuro: `adb shell cmd uimode night yes` (e `no` para voltar);
  - desligar no fim: `adb emu kill`.
- **Imagens de sistema:** só existem `android-36.1` e `android-35` (tablet). **Não baixe** a imagem do Android 30 sem perguntar ao dono, porque são uns 1 GB. Sem ela, a splash do Android 11 fica registrada como "não conferida no aparelho".
- `/snap/bin/dart` não enxerga `/tmp`.
- **Arquivos fora do git:** `logo.jpeg` (raiz) **não** vai para o git e **não** é mexido. `.superpowers/` também não vai para o git.
- **Commits:** um no fim de cada task, mensagem em inglês no formato `feat: ...` / `test: ...` / `chore: ...`. Antes de cada commit, `flutter analyze` sem avisos e `flutter test` todo passando.

## Review Focus

1. **Fonte do sistema grande** (Android "tamanho da fonte" até 200%). Esperado: os títulos quebram linha e os nomes e detalhes ganham reticências, sem faixa de overflow em Arquivos e Ajustes. Testado nas Tasks 6 e 7 com `TextScaler.linear(2)` numa tela de 360×690.
2. **Tema escuro ilegível**: texto ou ícone com a mesma cor do fundo, como SnackBar, segmento escolhido ou botão Escanear. Esperado: todos os pares texto/fundo do tema com contraste ≥ 4,5 e os cantos do botão Escanear com contraste ≥ 3 nos dois temas. Testado na Task 1.
3. **Último arquivo escondido atrás do botão Escanear**, que sobe 22 dp acima da barra. Esperado: rolando até o fim, a última linha fica inteira acima do topo do botão. Testado na Task 6.
4. **Agrupamento por dia na virada da meia-noite e do ano.** Esperado: o arquivo das 23:50 de ontem fica em "Ontem", inclusive de 31/12 para 01/01; uma data futura (relógio errado) não vira "Hoje". Testado na Task 2.
5. **Barra com navegação de 3 botões** (recuo inferior grande) e troca rápida de aba. Esperado: o topo do botão Escanear continua 22 dp acima da barra e recebendo toques, e a pílula termina embaixo da aba ativa mesmo com a animação interrompida. Testado na Task 5.

---

### Task 1: Tema, fontes e licenças

**Files:**
- Create: `lib/theme.dart`
- Create: `assets/fonts/Newsreader-Variable.ttf`, `assets/fonts/Outfit-Variable.ttf`, `assets/fonts/Newsreader-OFL.txt`, `assets/fonts/Outfit-OFL.txt`
- Modify: `pubspec.yaml` (seções `flutter.fonts` e `flutter.assets`)
- Modify: `lib/main.dart:16-26` (`main()` e `theme`/`darkTheme`)
- Test: `test/theme_test.dart`
- Commit também: `docs/superpowers/specs/2026-10-17-papyr-visual-design.md` e este plano.

**Interfaces:**
- Produces:
  - `abstract final class Brand` com as cores fixas: `navy = Color(0xFF102E50)`, `sky = Color(0xFF32B0FA)`, `green = Color(0xFF00FD9A)`, `paper = Color(0xFFF6F3EC)`, `night = Color(0xFF0E1A2A)`.
  - `ThemeData papyrTheme(Brightness brightness)`.
  - `TextStyle serif(double size, {double? height})`: Newsreader 500 com opsz = `size`. As Tasks 5 a 9 usam para títulos fora do `TextTheme`.
  - Mapeamento de papéis da spec §5.1 para `ColorScheme`, que as outras tasks usam pelo nome do papel do `ColorScheme`:

| spec §5.1 | `ColorScheme` | claro | escuro |
|---|---|---|---|
| fundo | `surface` | `F6F3EC` | `0E1A2A` |
| tinta | `primary`, `onSurface`, `inverseSurface` | `102E50` | `F1EEE6` |
| sobre a tinta | `onPrimary`, `onInverseSurface` | `F6F3EC` | `102E50` |
| botão Escanear | `primaryContainer` | `102E50` | `1F3A5F` |
| cantos do botão | `onPrimaryContainer` | `F6F3EC` | `F6F3EC` |
| folha | `surfaceContainerLowest` | `FFFFFF` | `16263B` |
| painel | `surfaceContainer` (e `surfaceContainerLow`) | `EEE9DD` | `1A2B42` |
| pílula | `surfaceContainerHigh` (e `surfaceContainerHighest`) | `E8E2D4` | `1E3150` |
| linha | `outlineVariant` | `E6E1D6` | `24364F` |
| cinza | `onSurfaceVariant` | `6B655A` | `A3ADBB` |
| inativo | `outline` | `8A8376` | `7F8DA3` |
| céu | `secondary` (`onSecondary` = `102E50`) | `32B0FA` | `32B0FA` |
| verde | `tertiary` (`onTertiary` = `102E50`) | `00FD9A` | `00FD9A` |
| erro | `error` (`onError` `FFFFFF` / `601410`) | `B3261E` | `F2B8B5` |

O `surfaceTint` é `Colors.transparent`.

- [ ] **Step 1: Write the failing test** `test/theme_test.dart`

```dart
Color c(int v) => Color(v);
double contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return (max(la, lb) + 0.05) / (min(la, lb) + 0.05);
}

test('light scheme uses the brand colors', () {
  final s = papyrTheme(Brightness.light).colorScheme;
  expect(s.surface, c(0xFFF6F3EC));
  expect(s.primary, c(0xFF102E50));
  expect(s.onPrimary, c(0xFFF6F3EC));
  expect(s.primaryContainer, c(0xFF102E50));
  expect(s.surfaceContainerLowest, c(0xFFFFFFFF));
  expect(s.surfaceContainer, c(0xFFEEE9DD));
  expect(s.surfaceContainerHigh, c(0xFFE8E2D4));
  expect(s.outlineVariant, c(0xFFE6E1D6));
  expect(s.onSurfaceVariant, c(0xFF6B655A));
  expect(s.outline, c(0xFF8A8376));
  expect(s.secondary, c(0xFF32B0FA));
  expect(s.tertiary, c(0xFF00FD9A));
  expect(s.error, c(0xFFB3261E));
});

test('dark scheme is "tinta à noite"', () {
  final s = papyrTheme(Brightness.dark).colorScheme;
  expect(s.surface, c(0xFF0E1A2A));
  expect(s.primary, c(0xFFF1EEE6));
  expect(s.onPrimary, c(0xFF102E50));
  expect(s.primaryContainer, c(0xFF1F3A5F));
  expect(s.onPrimaryContainer, c(0xFFF6F3EC));
  expect(s.surfaceContainerLowest, c(0xFF16263B));
  expect(s.surfaceContainer, c(0xFF1A2B42));
  expect(s.surfaceContainerHigh, c(0xFF1E3150));
  expect(s.outlineVariant, c(0xFF24364F));
  expect(s.onSurfaceVariant, c(0xFFA3ADBB));
  expect(s.outline, c(0xFF7F8DA3));
  expect(s.error, c(0xFFF2B8B5));
});

test('titles use Newsreader at their own optical size; the rest is Outfit', () {
  final t = papyrTheme(Brightness.light);
  void serifAt(TextStyle? s, double size) {
    expect(s!.fontFamily, 'Newsreader');
    expect(s.fontSize, size);
    expect(s.fontWeight, FontWeight.w500);
    expect(s.fontVariations, containsAll([FontVariation('opsz', size), const FontVariation('wght', 500)]));
  }
  serifAt(t.textTheme.headlineLarge, 34);
  serifAt(t.textTheme.headlineMedium, 28);
  serifAt(t.dialogTheme.titleTextStyle, 22);
  // AlertDialog uses this style as-is (it does not merge the ambient color): without a color the title paints white
  expect(t.dialogTheme.titleTextStyle!.color, t.colorScheme.onSurface);
  expect(t.textTheme.bodyMedium!.fontFamily, 'Outfit');
  expect(t.textTheme.titleMedium!.fontWeight, FontWeight.w500);
  expect(t.textTheme.labelLarge!.fontWeight, FontWeight.w600);
});

// Review Focus 2
for (final b in Brightness.values) {
  test('$b text pairs are legible', () {
    final s = papyrTheme(b).colorScheme;
    expect(contrast(s.onSurface, s.surface), greaterThanOrEqualTo(4.5));
    expect(contrast(s.onSurfaceVariant, s.surface), greaterThanOrEqualTo(4.5));
    expect(contrast(s.onSurfaceVariant, s.surfaceContainer), greaterThanOrEqualTo(4.5));
    expect(contrast(s.onPrimary, s.primary), greaterThanOrEqualTo(4.5));
    expect(contrast(s.onInverseSurface, s.inverseSurface), greaterThanOrEqualTo(4.5));
    expect(contrast(s.error, s.surface), greaterThanOrEqualTo(4.5));
    expect(contrast(s.onPrimaryContainer, s.primaryContainer), greaterThanOrEqualTo(3));
    expect(contrast(Brand.green, s.primaryContainer), greaterThanOrEqualTo(3));
  });
}
```

- [ ] **Step 2: Run** `flutter test test/theme_test.dart`. Expected: FAIL (`theme.dart` não existe).

- [ ] **Step 3: Baixar as fontes**
  - `https://github.com/google/fonts/raw/main/ofl/newsreader/Newsreader%5Bopsz,wght%5D.ttf` vira `assets/fonts/Newsreader-Variable.ttf`.
  - `https://github.com/google/fonts/raw/main/ofl/outfit/Outfit%5Bwght%5D.ttf` vira `assets/fonts/Outfit-Variable.ttf`.
  - Os `OFL.txt` das duas pastas viram `Newsreader-OFL.txt` e `Outfit-OFL.txt`.
  - Confira com `file assets/fonts/*.ttf`: tem que dar "TrueType Font data".
  - No `pubspec.yaml`:
    - `fonts`: família `Newsreader` com o asset `assets/fonts/Newsreader-Variable.ttf`, e família `Outfit` com `assets/fonts/Outfit-Variable.ttf`;
    - `assets`: os dois `.txt`. O `assets/brand/wordmark.png` entra na Task 4.

- [ ] **Step 4: Implement `lib/theme.dart`**
  - `papyrTheme` monta `ColorScheme(...)` com a tabela acima.
  - `fontFamily: 'Outfit'`.
  - `TextTheme` conforme a escala da spec §5.2:

| papel do `TextTheme` | fonte | tamanho / altura de linha | peso |
|---|---|---|---|
| `headlineLarge` | `serif` | 34 / 1,05, `letterSpacing: -0.34` | 500 |
| `headlineMedium` | `serif` | 28 / 1,1 | 500 |
| `titleMedium` | Outfit | 15 / 1,3 | 500 |
| `titleSmall` (rótulo de seção) | Outfit | 13 / 1,3, cor `onSurfaceVariant` | 500 |
| `bodyLarge` e `bodyMedium` | Outfit | 15 / 1,45 | 400 |
| `bodySmall` | Outfit | 12,5 / 1,3, cor `onSurfaceVariant` | 400 |
| `labelLarge` | Outfit | 15 | 600 |

  - Temas de componentes (spec §5.3 e §7.7):

| componente | ajustes |
|---|---|
| `scaffoldBackgroundColor` | `surface` |
| `appBarTheme` | fundo `surface`, `foregroundColor: onSurface`, `elevation: 0`, `scrolledUnderElevation: 0`, `surfaceTintColor: transparent` |
| `filledButtonTheme` | `StadiumBorder`, `minimumSize: Size(64, 52)` |
| `outlinedButtonTheme` | `StadiumBorder`, borda `outlineVariant` |
| `segmentedButtonTheme` | selecionado `primary`/`onPrimary`, borda `outlineVariant` |
| `snackBarTheme` | `floating`, raio 14, fundo `inverseSurface`, `elevation: 0` |
| `dialogTheme` | fundo `surface`, raio 24, `titleTextStyle: serif(22, height: 1.2).copyWith(color: onSurface)` |
| `popupMenuTheme` | cor `surfaceContainerLowest`, raio 14, `elevation: 0` |
| `progressIndicatorTheme` | cor `primary` |
| `inputDecorationTheme` | `filled`, `fillColor: surfaceContainer`, `OutlineInputBorder(raio 14, BorderSide.none)`, foco com borda `secondary` de 2 |

- [ ] **Step 5: Wire it in `lib/main.dart`**
  - `theme: papyrTheme(Brightness.light)` e `darkTheme: papyrTheme(Brightness.dark)`. Apague `_seed`.
  - Em `main()`, antes do `runApp`, um `LicenseRegistry.addLicense` que lê os dois `.txt` com `rootBundle.loadString` e devolve `LicenseEntryWithLineBreaks(['Newsreader'], …)` e `(['Outfit'], …)`.

- [ ] **Step 6: Run** `flutter test test/theme_test.dart` e depois `flutter test`. Expected: PASS. Os outros testes não dependem das cores.

- [ ] **Step 7: Commit**

```bash
git add lib/theme.dart lib/main.dart pubspec.yaml assets/fonts test/theme_test.dart docs/superpowers/specs/2026-10-17-papyr-visual-design.md docs/superpowers/plans/2026-10-17-papyr-visual.md
git commit -m "feat: add Papel e tinta theme with bundled Newsreader and Outfit"
```

---

### Task 2: Formatação (plural, hora, dia, espaço)

**Files:**
- Modify: `lib/format.dart`
- Test: `test/format_test.dart` (acrescentar)

**Interfaces:**
- Produces:
  - `String plural(int n, String one, String many)`: `'1 foto'`, `'0 fotos'`.
  - `String formatTime(DateTime t)`: `'09:05'`.
  - `String formatDay(DateTime t, DateTime now)`: `'Hoje'`, `'Ontem'`, `'15 de outubro'` ou `'15 de outubro de 2025'`. A comparação é por dia do calendário (ano, mês e dia locais), e não por 24 h.
  - `String? storageItems(int images, int pdfs)`: `'12 imagens e 3 PDFs'`, `'3 PDFs'`, `'1 imagem'` ou `null` quando os dois são 0.

- [ ] **Step 1: Write the failing tests**

```dart
test('plural', () {
  expect(plural(1, 'foto', 'fotos'), '1 foto');
  expect(plural(0, 'foto', 'fotos'), '0 fotos');
  expect(plural(12, 'arquivo', 'arquivos'), '12 arquivos');
});

test('formatTime', () => expect(formatTime(DateTime(2026, 1, 2, 9, 5)), '09:05'));

test('formatDay by calendar day (Review Focus 4)', () {
  final now = DateTime(2026, 10, 17, 0, 30);
  expect(formatDay(DateTime(2026, 10, 17, 0, 0), now), 'Hoje');
  expect(formatDay(DateTime(2026, 10, 16, 23, 50), now), 'Ontem');
  expect(formatDay(DateTime(2026, 10, 15, 12), now), '15 de outubro');
  expect(formatDay(DateTime(2026, 3, 1), now), '1 de março');
  expect(formatDay(DateTime(2026, 10, 18, 8), now), '18 de outubro'); // clock skew: never "Hoje"
  final newYear = DateTime(2026, 1, 1, 8);
  expect(formatDay(DateTime(2025, 12, 31, 23, 50), newYear), 'Ontem');
  expect(formatDay(DateTime(2025, 12, 30), newYear), '30 de dezembro de 2025');
});

test('storageItems', () {
  expect(storageItems(2, 1), '2 imagens e 1 PDF');
  expect(storageItems(12, 3), '12 imagens e 3 PDFs');
  expect(storageItems(0, 3), '3 PDFs');
  expect(storageItems(1, 0), '1 imagem');
  expect(storageItems(0, 0), isNull);
});
```

- [ ] **Step 2: Run** `flutter test test/format_test.dart`. Expected: FAIL (funções não definidas).
- [ ] **Step 3: Implement** em `lib/format.dart`, reusando `_two`. Os meses ficam numa lista constante: `janeiro, fevereiro, março, abril, maio, junho, julho, agosto, setembro, outubro, novembro, dezembro`. "Ontem" = o dia do calendário de `now` menos 1, calculado com `DateTime(now.year, now.month, now.day - 1)`.
- [ ] **Step 4: Run** `flutter test test/format_test.dart`. Expected: PASS.
- [ ] **Step 5: Commit** `feat: add plural, time, day and storage formatting`.

---

### Task 3: A marca em código (`PapyrMark`)

**Files:**
- Create: `lib/widgets/papyr_mark.dart`
- Test: `test/papyr_mark_test.dart`

**Interfaces:**
- Consumes: `Brand` (Task 1).
- Produces:
  - `class PapyrMark extends StatelessWidget`, com dois construtores:
    - `const PapyrMark({super.key, required double width})`: a marca completa;
    - `const PapyrMark.scan({super.key, required double width, required Color brackets})`: só os cantos (na cor `brackets`) e a linha verde com brilho.
  - `width` é a largura externa dos cantos de enquadramento. O widget mede `Size(width, width * markAspect)`.
  - `const double markAspect = 998 / 977`.
  - O brilho pode pintar um pouco fora da caixa. Não use `ClipRect`.

A geometria, as cores, as espessuras e a ordem de desenho estão no apêndice A da spec, nas coordenadas do `logo.jpeg`:
- a caixa externa vai de `x 535–1512` e `y 330–1328`, então a origem do widget é `(535, 330)` e a escala é `width / 977`;
- os cantos arredondados dos polígonos cortam `r` de cada lado do vértice e ligam com uma quadrática que usa o vértice como controle (raio 22 na folha e 12 na dobra);
- o painter trabalha em unidades do logo: `canvas.scale(width / 977)` e depois `canvas.translate(-535, -330)`. Traços (34, 26 e 90) e raios (22 e 12) vão com os valores do apêndice, sem escalar à mão;
- o brilho é a linha com traço 90, opacidade 0,7 e `MaskFilter.blur(BlurStyle.normal, 26)`, desenhada **depois** da folha. O sigma **não** é multiplicado pela escala: o sigma do blur está em coordenadas locais e a transformação do canvas já o escala. Multiplicar dá sigma × escala² e o brilho some.

- [ ] **Step 1: Write the failing test** `test/papyr_mark_test.dart`. Use um `RepaintBoundary` e `toImage` dentro de `t.runAsync`. Cada ponto do logo `(x, y)` é lido no pixel `((x-535)*s, (y-330)*s)`, com `s = 300/977`.

```dart
testWidgets('full mark: size and colors where the logo has them', (t) async {
  final key = GlobalKey();
  await t.pumpWidget(Center(child: RepaintBoundary(key: key, child: const PapyrMark(width: 300))));
  expect(t.getSize(find.byType(PapyrMark)), Size(300, 300 * markAspect));
  final px = await pixels(t, key); // helper: Color at a logo coordinate, via toImage(pixelRatio: 1) + ByteData
  expect(px(1024, 851), closeToColor(Brand.green));             // scan line
  expect(px(650, 347), closeToColor(Brand.sky));                // top-left bracket arm
  expect(px(900, 700), closeToColor(const Color(0xFFFFFFFF)));  // sheet
  expect(px(1056, 447), closeToColor(Brand.navy));              // sheet top edge
});

testWidgets('scan variant: brackets in the given color, no sheet', (t) async {
  // same harness with PapyrMark.scan(width: 300, brackets: Brand.paper)
  expect(px(650, 347), closeToColor(Brand.paper));
  expect(px(1024, 851), closeToColor(Brand.green));
  expect(px(900, 700).a, lessThan(0.05)); // transparent where the sheet would be
  expect(px(1024, 791).a, greaterThan(0.1)); // the glow, 60 units above the line (≈0.19 right, ≈0.02 if the sigma is scaled twice)
});
```

`closeToColor(c)` é um `Matcher` local com tolerância de 12/255 por canal. `pixels` e `closeToColor` ficam no próprio arquivo de teste.

- [ ] **Step 2: Run** `flutter test test/papyr_mark_test.dart`. Expected: FAIL (`PapyrMark` não existe).
- [ ] **Step 3: Implement** `lib/widgets/papyr_mark.dart` (um `CustomPainter` privado) conforme acima.
- [ ] **Step 4: Run** `flutter test test/papyr_mark_test.dart`. Expected: PASS.
- [ ] **Step 5: Commit** `feat: draw the Papyr mark in code`.

---

### Task 4: Gerador da marca, ícone adaptativo e splash

**Files:**
- Create: `tool/brand.py`, `tool/brand/reference.svg` (gerado)
- Create (gerados): `assets/brand/wordmark.png`, `android/app/src/main/res/drawable/ic_launcher_foreground.xml`, `drawable/ic_launcher_monochrome.xml`, `drawable/splash_mark.xml`, `drawable/splash_icon.xml`, `drawable-xhdpi/splash_branding.png`, `drawable-xxhdpi/splash_branding.png`, `drawable-xxxhdpi/splash_branding.png`
- Create (à mão): `res/mipmap-anydpi-v26/ic_launcher.xml`, `res/values/colors.xml`, `res/values-v31/styles.xml`, `res/values-night-v31/styles.xml`
- Modify: `res/values/styles.xml`, `res/values-night/styles.xml` (`NormalTheme`), `res/drawable-v21/launch_background.xml`
- Modify: `pubspec.yaml` (`assets`: `assets/brand/wordmark.png`)
- Delete: `res/drawable/launch_background.xml`, `res/mipmap-{m,h,xh,xxh,xxxh}dpi/ic_launcher.png`

**Interfaces:**
- Consumes: geometria da spec, apêndice A.
- Produces:
  - `assets/brand/wordmark.png`: branco com alfa, uns 982×305 px. A Task 7 usa.
  - `@drawable/ic_launcher_foreground`, `@drawable/ic_launcher_monochrome`, `@drawable/splash_mark`, `@drawable/splash_icon`, `@drawable/splash_branding`.
  - `@color/ic_launcher_background` (`#102E50`, o nome que a spec §8.2 usa, também usado na splash), `@color/window_light` (`#F6F3EC`), `@color/window_dark` (`#0E1A2A`).
  - `tool/brand/reference.svg`: a marca com o desfoque de verdade, versionada (spec §8.1).

**`tool/brand.py`:**
- Uso: `python3 -I tool/brand.py [--logo /caminho/logo.jpeg]`, rodado da raiz.
- Python padrão para SVG e XML. Pillow só para os PNGs.
- `--logo` refaz `wordmark.png` pela spec §8.4: corte `(480, 1380, 1570, 1790)`, alfa = `(255 − L)·255/(255 − 41)`, zerado abaixo de 10, e `getbbox`. Sem `--logo`, ele lê o `wordmark.png` que já existe.
- Escreve os VectorDrawables:
  - os caminhos do apêndice A vão como `pathData`, que aceita a mesma sintaxe de caminho do SVG;
  - um `<group>` com translate/scale põe o centro `(1024, 829)` no centro do viewport;
  - **`ic_launcher_foreground`**: 108×108 dp e escala tal que os 977 de largura viram **47 dp**. Viewport de lado `977·108/47`.
  - **`ic_launcher_monochrome`**: mesma escala, só traços, cor `#FF000000`, sem preenchimento e sem brilho.
  - **`splash_mark`**: 288×288 dp e 977 viram **136 dp**. Viewport de lado `977·288/136`.
  - **Brilho** (spec §8.1), atrás da linha:
    - um círculo com `radialGradient` (verde `#B300FD9A` até `#0000FD9A`) dentro de um `<group>` com `scaleY` perto de 0,15;
    - mais um retângulo com `linearGradient` vertical (`#00`, `#8C` e `#00` de alfa sobre `00FD9A`).
- **`splash_icon.xml`**: `animated-vector` com `android:drawable="@drawable/splash_mark"` e um alvo no `<group android:name="mark">`, com um animador inline (`aapt:attr`) `rotation` de 0 para 0 e 1 ms de duração.
- **`splash_branding.png`** em xhdpi, xxhdpi e xxxhdpi: 400×160, 600×240 e 800×320 px. Fundo transparente, o nome em `#F6F3EC` centralizado e com `136/200` da largura do quadro.
- **Prévias** em `build/brand/` (ignorado pelo git), renderizadas com `google-chrome --headless=new --screenshot --default-background-color=00000000`:
  - `glow.png`: lado a lado, a referência com `feGaussianBlur` e o equivalente em SVG dos mesmos gradientes;
  - `icon-circle.png` e `icon-squircle.png`: o ícone com as máscaras e o círculo de 66 dp da zona segura desenhado por cima;
  - `splash.png`: a splash composta, num celular de 412×915 dp.

**À mão:**
- **`mipmap-anydpi-v26/ic_launcher.xml`:** `<adaptive-icon>` com `background @color/ic_launcher_background`, `foreground @drawable/ic_launcher_foreground` e `monochrome @drawable/ic_launcher_monochrome`.
- **`values-v31/styles.xml`:** `LaunchTheme` com o mesmo `parent` de `values/` e os itens:
  - `android:windowSplashScreenBackground` = `@color/ic_launcher_background`;
  - `android:windowSplashScreenAnimatedIcon` = `@drawable/splash_icon`;
  - `android:windowSplashScreenAnimationDuration` = `200`;
  - `android:windowSplashScreenBrandingImage` = `@drawable/splash_branding`.
- **`values-night-v31/styles.xml`:** igual, com o `parent` de `values-night/`.
- **`NormalTheme`:** `windowBackground` = `@color/window_light` (em `values/`) ou `@color/window_dark` (em `values-night/`).
- **`drawable-v21/launch_background.xml`:** `layer-list` com três itens:
  - `@color/ic_launcher_background`;
  - `<item android:drawable="@drawable/splash_mark" android:width="288dp" android:height="288dp" android:gravity="center"/>`;
  - `<item android:drawable="@drawable/splash_branding" android:width="200dp" android:height="80dp" android:gravity="bottom|center_horizontal" android:bottom="60dp"/>`.

- [ ] **Step 1: Rode** `python3 -I tool/brand.py --logo logo.jpeg`. Expected: os arquivos acima existem, e `python3 -I -c "from PIL import Image; print(Image.open('assets/brand/wordmark.png').size)"` mostra uns `(982, 305)`.
- [ ] **Step 2: Olhe as prévias** (Read nas imagens de `build/brand/`).
  - `glow.png`: os dois brilhos têm que ser difíceis de distinguir no tamanho real.
  - `icon-*.png`: nada pode passar do círculo de 66 dp.
  - `splash.png`: a marca a 136 dp, o nome no rodapé e tudo nítido.
  - Ajuste os parâmetros do gradiente e rode de novo até ficar certo.
- [ ] **Step 3: Faça os arquivos à mão** e apague os listados em Delete.
- [ ] **Step 4: Build.** `nice -n 15 flutter build apk --debug`. Expected: sucesso, sem erro do aapt2.
- [ ] **Step 5: No emulador** (protocolo):
  - instale com `flutter install` ou `adb install -r build/app/outputs/flutter-apk/app-debug.apk`;
  - splash: `adb shell am force-stop com.pedroalves.papyr; adb shell am start -n com.pedroalves.papyr/.MainActivity; sleep 0.4` e screenshot. Repita até 5 vezes até pegar a splash;
  - ícone: abra a gaveta de apps e tire um screenshot do ícone. Repita em modo escuro;
  - conferir na splash: fundo marinho, a marca nítida (bordas sem serrilhado), cantos azuis e o nome cor de papel no rodapé;
  - conferir no ícone: a marca dentro do círculo, sem corte;
  - Android 11: se `~/Android/Sdk/system-images/android-30` não existir, registre "splash do Android 11 não conferida no aparelho" no relatório da task.
- [ ] **Step 6: Run** `flutter test` (sem regressão) e depois `adb emu kill`.
- [ ] **Step 7: Commit**

```bash
git add -A tool assets/brand/wordmark.png pubspec.yaml android/app/src/main/res
git commit -m "feat: vector launcher icon and navy splash from the Papyr mark"
```

---

### Task 5: Barra só com ícones, botão Escanear e voltar compartilhado

**Files:**
- Modify: `lib/widgets/snake_bar.dart` (reescrita)
- Modify: `lib/main.dart` (shell, `goBack`, região da barra de status)
- Test: `test/snake_bar_test.dart` (reescrita) e `test/shell_test.dart` (novo)

**Interfaces:**
- Consumes: `papyrTheme`, `Brand` (Task 1); `PapyrMark.scan` (Task 3); `plural` (Task 2).
- Produces:
  - **`SnakeBar`:** `SnakeBar({super.key, required int index, required ValueChanged<int> onTap, required List<(IconData, String)?> items})`.
    - Uma entrada `null` é uma coluna vazia, embaixo do botão Escanear.
    - `index` aponta sempre para uma entrada não nula.
    - A pílula tem `key: const ValueKey('pill')`.
  - **`ScanButton`:** `ScanButton({super.key, required VoidCallback onPressed})`, de 62×62.
  - **`scanButtonLocation`:** `const FloatingActionButtonLocation scanButtonLocation`, que põe o botão centrado na horizontal e com o topo em `contentBottom - 22`.
  - **`goBack`:** `Future<void> goBack(BuildContext context)`, em `lib/main.dart`. É o antigo `_back`, agora público. A Task 8 usa no X.
    - Na aba 1 com fotos, pergunta `'Descartar ${plural(n, 'foto', 'fotos')}?'`, com os botões "Cancelar" e "Descartar" (este na cor `error`).
    - Nos outros casos, `tab.value = 0`.

**Barra** (spec §6):
- `Material(color: surface, shape: Border(top: BorderSide(color: outlineVariant)))`. A linha é só pintura e não ocupa espaço, então a linha dos ícones continua com os 64 dp inteiros.
- Altura 64 mais `MediaQuery.viewPaddingOf(context).bottom`.
- Três `Expanded`. Cada item não nulo é um `Semantics(button, selected, label)`, mais `Tooltip(label)`, mais um `InkWell` que preenche a coluna inteira na altura de 64. O ícone tem 24 dp, em `primary` quando ativo e em `outline` quando não.
- Pílula: 64×44, raio 22, cor `surfaceContainerHigh`, centrada no item.
- A animação snake continua a de hoje, com os mesmos intervalos e 400 ms. As bordas em "slots" viram pixels assim: `left = l*w + (w-64)/2` e `right = r*w - (w-64)/2`.
- Com `MediaQuery.disableAnimationsOf(context)`, `_c.value = 1` direto.

**Botão Escanear:**
- `Material(color: primaryContainer, borderRadius: 21)` dentro de um `DecoratedBox` com a sombra da spec §6 (claro `0 8 18 rgba(16,46,80,.3)`, escuro `rgba(0,0,0,.4)`).
- `InkWell`, `Semantics(button: true, label: 'Escanear')` e `Tooltip('Escanear')`.
- No meio, `PapyrMark.scan(width: 29, brackets: onPrimaryContainer)`.

**Shell (`main.dart`):**
- `floatingActionButton: index == 1 ? const SizedBox.shrink() : ScanButton(onPressed: () => tab.value = 1)` e `floatingActionButtonLocation: scanButtonLocation`.
  - Use `SizedBox.shrink()`, e **não `null`**: trocar `null` por widget dispara a animação de entrada e saída do FAB (encolhe e gira 45°), que ignora `disableAnimations`. Dois filhos não nulos e sem key trocam na hora.
- `bottomNavigationBar: index == 1 ? null : SnakeBar(index: index, onTap: …, items: const [(Icons.folder_outlined, 'Arquivos'), null, (Icons.settings_outlined, 'Ajustes')])`.
- O Scaffold fica envolto em `AnnotatedRegion<SystemUiOverlayStyle>`:
  - no tema claro, `SystemUiOverlayStyle.dark.copyWith(statusBarColor: Colors.transparent, systemNavigationBarColor: Colors.transparent, systemNavigationBarIconBrightness: Brightness.dark)`. O `.dark` sozinho deixa os botões de navegação do sistema claros, e eles somem sobre a barra cor de papel;
  - no escuro, `SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent, systemNavigationBarColor: Colors.transparent)`.

- [ ] **Step 1: Write the failing tests.**

`test/snake_bar_test.dart`. Use um host `Scaffold(floatingActionButton: ScanButton(onPressed: () => tapped = 1), floatingActionButtonLocation: scanButtonLocation, bottomNavigationBar: SnakeBar(index: i, onTap: (v) => tapped = v, items: const [(Icons.folder_outlined, 'Arquivos'), null, (Icons.settings_outlined, 'Ajustes')]))` dentro de `MaterialApp(theme: papyrTheme(Brightness.light))`, com `index` vindo de um `ValueNotifier` para trocar sem remontar.

```dart
testWidgets('side items fill their column: centred, tappable near the bottom edge', (t) async {
  // unchanged intent from today's test
  final bar = t.getRect(find.byType(SnakeBar));
  expect(t.getCenter(find.byIcon(Icons.folder_outlined)).dy, bar.center.dy);
  expect(t.getCenter(find.byIcon(Icons.settings_outlined)).dy, bar.center.dy);
  await t.tapAt(Offset(t.getCenter(find.byIcon(Icons.settings_outlined)).dx, bar.bottom - 10));
  expect(tapped, 2);
});

testWidgets('Arquivos column takes the tap back from Ajustes', (t) async {
  index.value = 2; await t.pumpAndSettle();
  await t.tap(find.byIcon(Icons.folder_outlined));
  expect(tapped, 0);
});

testWidgets('three items evenly spaced', (t) async {
  final w = t.getSize(find.byType(SnakeBar)).width;
  expect(t.getCenter(find.byIcon(Icons.folder_outlined)).dx, closeTo(w / 6, 0.5));
  expect(t.getCenter(find.byType(ScanButton)).dx, closeTo(w / 2, 0.5));
  expect(t.getCenter(find.byIcon(Icons.settings_outlined)).dx, closeTo(5 * w / 6, 0.5));
});

// Review Focus 5: with a 3-button nav inset too
for (final inset in [0.0, 48.0]) {
  testWidgets('scan button rises 22 dp and its raised top takes taps (inset $inset)', (t) async {
    // pump the host under MediaQuery(viewPadding: EdgeInsets.only(bottom: inset), padding: same)
    final bar = t.getRect(find.byType(SnakeBar));
    final scan = t.getRect(find.byType(ScanButton));
    expect(scan.top, bar.top - 22);
    expect(scan.size, const Size(62, 62));
    await t.tapAt(Offset(scan.center.dx, scan.top + 4));
    expect(tapped, 1);
  });
}

testWidgets('labels for screen readers and tap targets', (t) async {
  expect(find.bySemanticsLabel('Arquivos'), findsOneWidget);
  expect(find.bySemanticsLabel('Escanear'), findsOneWidget);
  expect(find.bySemanticsLabel('Ajustes'), findsOneWidget);
  expect(find.text('Arquivos'), findsNothing); // no visible label
  await expectLater(t, meetsGuideline(androidTapTargetGuideline));
});

// Review Focus 5
testWidgets('pill ends under the active item after an interrupted switch', (t) async {
  index.value = 2; await t.pump(const Duration(milliseconds: 100));
  index.value = 0; await t.pumpAndSettle();
  expect(t.getCenter(find.byKey(const ValueKey('pill'))).dx, closeTo(t.getCenter(find.byIcon(Icons.folder_outlined)).dx, 0.5));
});

testWidgets('reduced motion: pill jumps', (t) async {
  // host under MediaQuery(disableAnimations: true)
  index.value = 2; await t.pump();
  expect(t.getCenter(find.byKey(const ValueKey('pill'))).dx, closeTo(t.getCenter(find.byIcon(Icons.settings_outlined)).dx, 0.5));
});
```

`test/shell_test.dart`. O host é `MaterialApp(home: Builder(builder: (c) => TextButton(onPressed: () => goBack(c), child: const Text('voltar'))))`, com o canal `papyr/native` mockado e as chamadas registradas.

```dart
testWidgets('Ajustes and empty Escanear go back to Arquivos', (t) async {
  for (final from in [2, 1]) { tab.value = from; session.clear(); /* tap voltar */ expect(tab.value, 0); }
});

testWidgets('Escanear with photos asks; Cancelar keeps, Descartar clears', (t) async {
  tab.value = 1; session..clear()..add(Photo('/c/a.jpg'))..add(Photo('/c/b.jpg'));
  // tap voltar
  expect(find.text('Descartar 2 fotos?'), findsOneWidget);
  await t.tap(find.text('Cancelar')); await t.pumpAndSettle();
  expect((tab.value, session.photos.length), (1, 2));
  // tap voltar, then Descartar
  expect((tab.value, session.photos.length), (0, 0));
  expect(calls.map((c) => c.method), contains('cleanCache'));
});

testWidgets('one photo is singular', (t) async {
  tab.value = 1; session..clear()..add(Photo('/c/a.jpg'));
  // tap voltar
  expect(find.text('Descartar 1 foto?'), findsOneWidget);
});
```

- [ ] **Step 2: Run** `flutter test test/snake_bar_test.dart test/shell_test.dart`. Expected: FAIL (`ScanButton`, `scanButtonLocation` e `goBack` não existem).
- [ ] **Step 3: Implement** `snake_bar.dart` e o shell em `main.dart` conforme acima.
- [ ] **Step 4: Run** `flutter test`. Expected: PASS. Em `test/settings_screen_test.dart`, o teste `'tab 2 is the settings screen'` ganha `expect(find.byType(SnakeBar), findsOneWidget)` e `expect(find.byType(ScanButton), findsOneWidget)`.
- [ ] **Step 5: Commit** `feat: icon-only nav bar with raised scan button`.

---

### Task 6: Arquivos

**Files:**
- Modify: `lib/files/files_screen.dart`
- Test: `test/files_screen_test.dart`

**Interfaces:**
- Consumes: `plural`, `formatDay`, `formatTime`, `formatSize` (Task 2); `PapyrMark` (Task 3); `ScanButton`, `scanButtonLocation`, `SnakeBar` (Task 5, só no teste do Review Focus 3).
- Produces: nada novo. `confirmDelete`, `deleteItem`, `closeGone` e `closeRoute` mantêm as assinaturas.

Layout (spec §7.1):
- `RefreshIndicator` envolvendo um `CustomScrollView`, sem AppBar e com `SafeArea(bottom: false)` no topo.
- Cabeçalho com padding horizontal de 20:
  - `PapyrMark(width: 30)`, 10 dp abaixo da área segura;
  - 14 dp depois, `Text('Seus documentos', style: headlineLarge)`;
  - 4 dp depois, `Text('${plural(n, 'arquivo', 'arquivos')}, ${formatSize(total)}', style: bodySmall)`.
- Para cada dia em sequência (a lista já vem em ordem decrescente de data):
  - o rótulo `formatDay(item.date, DateTime.now())` em `titleSmall`, com padding `(20, 16, 20, 6)`;
  - as linhas daquele dia.
- No fim, `SliverPadding(bottom: 24)`.
- **Linha:**
  - `InkWell` com padding `(20, 9)`;
  - miniatura de 38×52, raio 4, borda de 1 dp em `outlineVariant`, `BoxFit.cover`. O placeholder é fundo `surfaceContainerLowest` com o ícone do tipo em `outline`, 18 dp;
  - 14 dp de espaço e depois o nome (`titleMedium`, 1 linha, reticências);
  - embaixo do nome, `'${item.isPdf ? 'PDF' : 'Imagem'}, ${formatSize(item.size)}, ${formatTime(item.date)}'` (`bodySmall`, 1 linha);
  - por último, o `PopupMenuButton` de sempre. O item "Excluir" fica com `TextStyle(color: error)`.
- O botão "Excluir" do `confirmDelete` também vai em `error`.
- **Estado vazio:** substitui o conteúdo rolável **inteiro, inclusive o cabeçalho**, como no modelo. Mostra `PapyrMark(width: 120)`, depois `'Nada escaneado ainda'` (`headlineMedium`) e `'Toque no botão do meio para fotografar sua primeira folha.'` (`bodyMedium`, `onSurfaceVariant`, centralizado, largura máxima de 240). **Sem botão.**
- Apague o `import 'package:papyr/main.dart'`, que fica sem uso, senão o `flutter analyze` avisa.
- **Erro:** a mesma composição, com `'Não foi possível carregar os arquivos.'` e um `FilledButton('Tentar de novo')` que chama `library.refresh`.

- [ ] **Step 1: Atualize e acrescente os testes** em `test/files_screen_test.dart`. O `pump` passa a usar `MaterialApp(theme: papyrTheme(Brightness.light), home: Scaffold(body: FilesScreen()))`.

```dart
testWidgets('empty list points to the scan button', (t) async {
  items = []; await pump(t);
  expect(find.text('Nada escaneado ainda'), findsOneWidget);
  expect(find.text('Toque no botão do meio para fotografar sua primeira folha.'), findsOneWidget);
  expect(find.byType(FilledButton), findsNothing);
  expect(find.byType(PapyrMark), findsOneWidget);
});

testWidgets('rows grouped by day with type, size and time; failed thumbnail shows placeholder', (t) async {
  // same two items as today (Contrato.pdf 17/10 14:05 12897485 B; Recibo.jpg 16/10 09:00 1536 B)
  await pump(t);
  final now = DateTime.now();
  final d17 = formatDay(DateTime(2026, 10, 17, 14, 5), now), d16 = formatDay(DateTime(2026, 10, 16, 9), now);
  expect(find.text('Seus documentos'), findsOneWidget);
  expect(find.text('2 arquivos, 12,3 MB'), findsOneWidget);
  expect(find.text('PDF, 12,3 MB, 14:05'), findsOneWidget);
  expect(find.text('Imagem, 1,5 KB, 09:00'), findsOneWidget);
  expect(find.text('IMG'), findsNothing);
  double y(Finder f) => t.getTopLeft(f).dy;
  expect(y(find.text(d17)), lessThan(y(find.text('Contrato.pdf'))));
  expect(y(find.text('Contrato.pdf')), lessThan(y(find.text(d16))));
  expect(y(find.text(d16)), lessThan(y(find.text('Recibo.jpg'))));
  expect(t.takeException(), isNull);
});

testWidgets('load error offers retry', (t) async {
  // the list handler throws PlatformException(code: 'io')
  expect(find.text('Não foi possível carregar os arquivos.'), findsOneWidget);
  await t.tap(find.widgetWithText(FilledButton, 'Tentar de novo')); await t.pumpAndSettle();
  expect(calls.where((c) => c.method == 'list').length, 2);
});

// Review Focus 1
testWidgets('200% text on a 360 dp phone does not overflow', (t) async {
  t.view..physicalSize = const Size(360, 690)..devicePixelRatio = 1;
  addTearDown(t.view.reset);
  // pump under MediaQuery(textScaler: TextScaler.linear(2)) with a long name: 'Contrato de locação residencial assinado' * 3
  expect(t.takeException(), isNull);
});

// Review Focus 3
testWidgets('last row clears the scan button', (t) async {
  // 30 items; host = Scaffold(body: FilesScreen(), floatingActionButton: ScanButton(...), floatingActionButtonLocation: scanButtonLocation, bottomNavigationBar: SnakeBar(...))
  await t.drag(find.byType(CustomScrollView), const Offset(0, -10000)); await t.pumpAndSettle();
  final last = t.getRect(find.ancestor(of: find.text('item29.jpg'), matching: find.byType(InkWell)).first);
  expect(last.bottom, lessThanOrEqualTo(t.getRect(find.byType(ScanButton)).top));
});
```

O teste de excluir de hoje continua, terminando com `expect(find.text('Nada escaneado ainda'), findsOneWidget)`.

O `setUp` passa a zerar o singleton: `library.items = []; library.error = null;`. Ele também zera a flag que faz `list` falhar. Sem isso, 'load error offers retry' vê as linhas do teste anterior, porque `refresh()` mantém os `items` antigos quando `list` falha.

- [ ] **Step 2: Run** `flutter test test/files_screen_test.dart`. Expected: FAIL nos textos novos.
- [ ] **Step 3: Implement** o layout acima em `files_screen.dart`.
- [ ] **Step 4: Run** `flutter test`. Expected: PASS, incluindo `viewers_test.dart`, que abre as linhas pelo nome.
- [ ] **Step 5: Commit** `feat: restyle Arquivos with day groups and the mark`.

---

### Task 7: Ajustes

**Files:**
- Modify: `lib/settings_screen.dart`
- Test: `test/settings_screen_test.dart`

**Interfaces:**
- Consumes: `storageItems`, `formatSize` (Task 2); `PapyrMark` (Task 3); `assets/brand/wordmark.png` (Task 4); `native.appVersion`; `ScanButton`, `scanButtonLocation`, `SnakeBar` (Task 5, só no teste do rodapé).

Layout (spec §7.2):
- `CustomScrollView` com `SafeArea(bottom: false)` e padding horizontal de 20. Os itens, em ordem:
  1. **Título:** `'Ajustes'` (`headlineLarge`), 18 dp abaixo da área segura.
  2. **Espaço usado:** o rótulo `'Espaço usado'` (`titleSmall`) e a frase `Text.rich`:
     - com arquivos: `[TextSpan(formatSize(total), w600), ' em ', storageItems(img, pdf)]`;
     - sem arquivos: `'Nada salvo ainda'`.
  3. **Medidor** (`key: ValueKey('meter')`), só quando houver arquivos:
     - altura 8, `ClipRRect` totalmente arredondado, fundo `surfaceContainerHigh`;
     - segmentos proporcionais aos bytes: imagens em `primary` e PDFs em `secondary`, com 2 dp de espaço entre eles quando houver os dois.
  4. **Legenda:** só para os tipos que não estão zerados, um quadradinho de 8 dp na cor do segmento e o texto `'Imagens ${formatSize(b)}'` ou `'PDFs ${formatSize(b)}'` (`bodySmall`).
  5. **Onde ficam os arquivos:** o rótulo `'Onde ficam os arquivos'` e duas linhas (sem toque), separadas por uma linha fina `outlineVariant`:
     - `Icons.image_outlined`, `'Imagens'` (`titleMedium`) e `'Pictures/Papyr'` (`bodySmall`);
     - `Icons.description_outlined`, `'PDFs'` e `'Documents/Papyr'`.
  6. **Aviso:** quadro `surfaceContainer`, raio 14, padding `(14, 12)`, `Icons.info_outline` de 18 dp e `'Desinstalar o Papyr não apaga seus arquivos, mas eles deixam de aparecer aqui.'` (`bodySmall`).
  7. **Rodapé:** `SliverFillRemaining(hasScrollBody: false)` alinhado embaixo, com:
     - `PapyrMark(width: 32)`;
     - `Image.asset('assets/brand/wordmark.png', height: 22, color: primary, colorBlendMode: BlendMode.srcIn, semanticLabel: 'Papyr')`;
     - `'Versão ${version}'` (`bodySmall`), com **padding de 40 embaixo**: 18 de respiro mais os 22 dp em que o botão Escanear invade o conteúdo, para o rodapé centralizado não ficar escondido atrás dele.

- [ ] **Step 1: Reescreva os testes** em `test/settings_screen_test.dart`. Use o mesmo mock de hoje, com `list` mutável:

```dart
testWidgets('shows space used, folders, note and version', (t) async {
  // list: a.jpg 1048576, b.jpg 524288, c.pdf 1048576
  expect(find.text('Ajustes'), findsOneWidget);
  expect(find.text('Espaço usado'), findsOneWidget);
  expect(find.text('2,5 MB em 2 imagens e 1 PDF', findRichText: true), findsOneWidget);
  expect(find.byKey(const ValueKey('meter')), findsOneWidget);
  expect(find.text('Imagens 1,5 MB'), findsOneWidget);
  expect(find.text('PDFs 1,0 MB'), findsOneWidget);
  expect(find.text('Onde ficam os arquivos'), findsOneWidget);
  for (final s in ['Imagens', 'Pictures/Papyr', 'PDFs', 'Documents/Papyr']) {
    expect(find.text(s), findsOneWidget);
  }
  expect(find.text('Desinstalar o Papyr não apaga seus arquivos, mas eles deixam de aparecer aqui.'), findsOneWidget);
  expect(find.text('Versão 1.0.0'), findsOneWidget);
  expect(find.bySemanticsLabel('Papyr'), findsOneWidget);
  expect(find.byType(PapyrMark), findsOneWidget);
});

testWidgets('nothing saved hides the meter', (t) async {
  // list: []
  expect(find.text('Nada salvo ainda'), findsOneWidget);
  expect(find.byKey(const ValueKey('meter')), findsNothing);
  expect(find.textContaining('Imagens 0'), findsNothing);
});

testWidgets('only PDFs leaves images out', (t) async {
  // list: c.pdf 1048576
  expect(find.text('1,0 MB em 1 PDF', findRichText: true), findsOneWidget);
  expect(find.textContaining('Imagens '), findsNothing);
});

// Review Focus 1
testWidgets('200% text on a 360 dp phone does not overflow', (t) async { /* as in Task 6 */ });

// Review Focus 3: the centred colophon sits right where the scan button rises
testWidgets('version clears the scan button', (t) async {
  // host = Scaffold(body: SettingsScreen(), floatingActionButton: ScanButton(...), floatingActionButtonLocation: scanButtonLocation, bottomNavigationBar: SnakeBar(...))
  await t.drag(find.byType(CustomScrollView), const Offset(0, -10000)); await t.pumpAndSettle(); // fits or not, check at the end
  expect(t.getRect(find.text('Versão 1.0.0')).bottom, lessThanOrEqualTo(t.getRect(find.byType(ScanButton)).top));
});
```

O teste `'tab 2 is the settings screen'` continua, com as duas expectativas da Task 5.

- [ ] **Step 2: Run** `flutter test test/settings_screen_test.dart`. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `flutter test`. Expected: PASS.
- [ ] **Step 5: Commit** `feat: restyle Ajustes with storage meter and colophon`.

---

### Task 8: Escanear em tela cheia

**Files:**
- Modify: `lib/scan/camera_screen.dart` (`build`, `_preview`, `_strip`, `_thumb`, `_controls`, `_Shutter`, `QuadPainter`)
- Test: `test/camera_lifecycle_test.dart` (novos cenários dentro do único `testWidgets`)

**Interfaces:**
- Consumes: `goBack` (Task 5); `plural` (Task 2); `Brand` (Task 1); `PapyrApp`, `SnakeBar` e `ScanButton` (só no teste).

Mudanças (spec §7.3):
- **`build`:** `SafeArea` com `bottom: true` (hoje é `false`).
- **`_preview`:** o indicador de "Abrindo câmera…" fica `CircularProgressIndicator(color: Brand.paper)`. O tema usa `primary`, que no claro é marinho e some no preto. Sobre o preview, no canto superior esquerdo, `Positioned(left: 14, top: 12)` com `IconButton(tooltip: 'Fechar', onPressed: () => goBack(context), style: IconButton.styleFrom(backgroundColor: Colors.black45, foregroundColor: Colors.white), icon: const Icon(Icons.close))`. Ele aparece também nos estados "Abrindo câmera…" e de erro.
- **`QuadPainter`:** cor `Brand.green`. Antes do traço de 3, desenha o mesmo caminho com traço 8, `Brand.green` com alfa 0,45 e `MaskFilter.blur(BlurStyle.normal, 6)`.
- **`_thumb`:** 34×46, raio 3.
  - O remover é um `IconButton(tooltip: 'Remover foto', style: IconButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(16, 16), fixedSize: const Size(16, 16), tapTargetSize: MaterialTapTargetSize.padded, backgroundColor: const Color(0xFF2A2A2A), foregroundColor: Colors.white), icon: const Icon(Icons.close, size: 12))`.
  - **Sem `VisualDensity.compact`**: ele encolhe a área de toque para 40 e quebra o mínimo de 48.
- **`_strip`:** a contagem vira `plural(photos.length, 'foto', 'fotos')`, alinhada à direita.
- **`_controls`:**
  - padding `(14, 12, 14, 26)`;
  - lanterna: `IconButton` com `style` de fundo `Colors.white.withValues(alpha: 0.08)` e 44 dp, mantendo o tooltip `'Lanterna'`;
  - **`_Shutter`:** 74 dp, borda `Brand.paper` de 4 e disco `Brand.paper`. Quando desabilitado, o disco fica `Brand.paper` com alfa 0,38;
  - `'Concluir (n)'`: `FilledButton` com fundo `Brand.paper` e texto `Brand.navy`. Desabilitado: fundo paper com alfa 0,24 e texto navy com alfa 0,38.
- **Estado de erro:** os botões ficam no mesmo estilo (paper e navy).

- [ ] **Step 1: Acrescente os cenários** em `test/camera_lifecycle_test.dart`. O mock do canal também responde `cleanCache` com `null` e `list` com `[]`.

```dart
// the strip counts in Portuguese
Future<void> count(WidgetTester t) async {
  fresh(); session.add(Photo('/c/CAP0.jpg'));
  await pumpHost(t); await settle(t);
  expect(find.text('1 foto'), findsOneWidget);
  await leave(t);
}

// X with no photos goes to Arquivos
Future<void> close(WidgetTester t) async {
  fresh(); tab.value = 1;
  await pumpHost(t); await settle(t);
  await t.tap(find.byTooltip('Fechar')); await settle(t);
  expect(tab.value, 0);
  await leave(t);
}

// the shell hides the bar and the scan button on Escanear and brings them back after X
Future<void> shell(WidgetTester t) async {
  fresh(); tab.value = 1;
  await t.pumpWidget(const PapyrApp()); await settle(t);
  expect(find.byType(SnakeBar), findsNothing);
  expect(find.byType(ScanButton), findsNothing);
  await t.tap(find.byTooltip('Fechar')); await settle(t);
  expect(find.byType(SnakeBar), findsOneWidget);
  expect(find.byType(ScanButton), findsOneWidget);
  await t.pumpWidget(const SizedBox()); await settle(t); // dispose the camera before the next scenario
}
```

Chame os três no `testWidgets('camera lifecycle …')`, depois dos cenários que já existem.

- [ ] **Step 2: Run** `flutter test test/camera_lifecycle_test.dart`. Expected: FAIL (`'1 foto'` e `'Fechar'` não existem).
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `flutter test`. Expected: PASS, incluindo `camera_screen_test.dart`, que pinta o `QuadPainter`.
- [ ] **Step 5: Commit** `feat: full-screen camera with close button`.

---

### Task 9: Salvar, editor de recorte e visualizadores

**Files:**
- Modify: `lib/scan/save_screen.dart`, `lib/scan/crop_screen.dart`, `lib/files/image_viewer.dart`, `lib/files/pdf_viewer.dart`
- Test: `test/save_screen_test.dart` (acrescentar 1)

**Interfaces:**
- Consumes: `Brand`, `serif` (Task 1); `PapyrMark` (Task 3).

**Salvar** (spec §7.5):
- `AppBar()` sem título e sem mudar a cor (o tema já usa `surface`). **Não** use `backgroundColor: Colors.transparent`: o AppBar calcula a cor dos ícones da barra de status pela cor do fundo, e transparente conta como escuro, o que deixa os ícones claros sobre o papel.
- Nos estágios `editing`, `processing` e `error`, o corpo começa com `Text('Salvar', style: headlineLarge)` e 20 dp de espaço.
- `done`: `PapyrMark(width: 72)` no lugar do ícone de check, e `'Salvo'` em `headlineMedium`.
- Os campos e botões pegam o estilo do tema (Task 1). Os textos e a lógica não mudam.

**Editor de recorte** (spec §7.4), sempre escuro:
- `Scaffold` e `AppBar` com fundo `Brand.night` e `foregroundColor: Brand.paper`. O título é `'n de N'` com `TextStyle(fontWeight: w500)`.
- `_QuadPainter`: preenchimento `Brand.green` com alfa 0,15 e traço `Brand.green`.
- `_Handle`: borda `Brand.green` e miolo `Brand.paper` com alfa 0,3.
- Lupa: `BorderSide(color: Brand.paper, width: 2)`.
- Na barra de baixo, os `TextButton` ficam com `foregroundColor: Brand.paper`. `'Continuar'` é um `FilledButton` com fundo `Brand.paper` e texto `Brand.navy`.
- Os textos de erro e o indicador de carregamento (`CircularProgressIndicator(color: Brand.paper)`) ficam em `Brand.paper`. O `FilledButton('Remover')` do erro fica no estilo de `'Continuar'`.

**Visualizadores** (spec §7.6):
- `viewerBar` e o `Scaffold` com fundo `Brand.night`, `foregroundColor: Brand.paper`, e o título em `w500`.
- No PDF, o contador vira uma pílula `Color(0x99000000)` com raio 16 e texto `Brand.paper` em `w500`.
- Os textos de erro e o indicador ficam em `Brand.paper`.

- [ ] **Step 1: Write the failing test** em `test/save_screen_test.dart`, junto do fluxo de sucesso que já existe:

```dart
testWidgets('done shows the mark and Salvo', (t) async {
  // same setup as the existing success test, then:
  expect(find.text('Salvo'), findsOneWidget);
  expect(find.byType(PapyrMark), findsOneWidget);
  expect(find.byIcon(Icons.check_circle_outline), findsNothing);
});
```

- [ ] **Step 2: Run** `flutter test test/save_screen_test.dart`. Expected: FAIL.
- [ ] **Step 3: Implement** as quatro telas.
- [ ] **Step 4: Run** `flutter test`. Expected: PASS. Os testes de recorte, visualizadores e salvar procuram os mesmos textos de antes.
- [ ] **Step 5: Commit** `feat: restyle save, crop editor and viewers`.

---

### Task 10: Conferência no aparelho e build de release

**Files:** nenhum, a não ser os ajustes que a conferência pedir. Um ajuste que mude texto ou layout volta para a task dona dele e para os testes dela.

- [ ] **Step 1:** Rode `flutter analyze` (sem avisos) e `flutter test` (tudo PASS).
- [ ] **Step 2:** `nice -n 15 flutter build apk --release`. Expected: sucesso.
  - `aapt2 dump permissions build/app/outputs/flutter-apk/app-release.apk` sem `INTERNET`.
  - `unzip -l` do APK com `flutter_assets/assets/fonts/Newsreader-Variable.ttf`, `Outfit-Variable.ttf` e `assets/brand/wordmark.png`.
- [ ] **Step 3: No emulador** (protocolo), tire screenshots e olhe cada um:
  - **tema claro:** Arquivos vazio, Arquivos com 3 arquivos de dias diferentes (escaneie de verdade), Ajustes, câmera, editor, Salvar e Salvo, visualizador de PDF, o diálogo de excluir e o SnackBar acima do botão Escanear;
  - **tema escuro** (`cmd uimode night yes`): Arquivos, Ajustes, o botão Escanear e o diálogo;
  - **navegação de 3 botões** (`adb shell cmd overlay enable com.android.internal.systemui.navbar.threebutton`; volte com `…navbar.gestural`): os botões do sistema escuros sobre a barra clara e claros no tema escuro, e o topo do botão Escanear recebendo toque;
  - **ícone:** gaveta de apps nos dois temas e, se o launcher do emulador tiver a opção, com "ícones temáticos" ligados (Configurações > Papel de parede e estilo). Se não tiver, registre que a camada monocromática não foi conferida no aparelho;
  - **splash:** como na Task 4, Step 5.
- [ ] **Step 4: Compare com a spec e os modelos.** Os modelos são `.superpowers/brainstorm/158878-1792276985/content/direcao.html`, `telas-v3.html`, `icone-ajustes-v2.html` e `icone-splash-v2.html`. Confira:
  - serifa nos títulos (com o corte de display visível no "Seus documentos");
  - a pílula sem texto;
  - o botão 22 dp acima da barra;
  - nenhum Material padrão sobrando (roxo, verde-azulado ou `ListTile` cinza).
- [ ] **Step 5:** `adb emu kill`. Escreva no relatório o que foi conferido e o que não foi, por exemplo a splash do Android 11 sem a imagem de sistema.
- [ ] **Step 6:** Se houve ajustes, commit `fix: ...` por ajuste, cada um com o teste da task dona.
