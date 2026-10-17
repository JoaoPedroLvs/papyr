# Papyr — Design

- Data: 2026-10-17
- Status: aguardando revisão (v2, depois da verificação técnica)
- Plataforma: Android apenas (celulares), Flutter 3.44.5 / Dart 3.12.2 (toolchain local da máquina)
- Notas da verificação, com snippets testados: `2026-10-17-papyr-verification-notes.md`

## 1. Objetivo

Aplicativo Android para escanear documentos, 100% offline e sem conta. A pessoa fotografa uma ou mais folhas com a câmera do próprio app, ajusta o recorte se quiser e salva o resultado como imagens ou como um PDF na memória pública do aparelho, sem reduzir a resolução.

## 2. Requisitos

Definidos pelo usuário:

1. App Flutter, somente Android. Nome **Papyr**, package `com.pedroalves.papyr`.
2. Navegação por barra no estilo "Snake Navigation Bar" com 3 abas: **Arquivos | Escanear | Ajustes**. O app abre em Arquivos.
3. 100% offline: sem login, sem conta e sem permissão de internet.
4. Câmera própria (não a câmera do sistema, não o scanner pronto do ML Kit), com:
   - botão de flash (lanterna);
   - várias fotos por sessão;
   - contorno da folha detectado e desenhado ao vivo sobre o preview.
5. Depois da câmera, uma etapa em que a pessoa pode ajustar manualmente os 4 cantos do recorte de cada foto.
6. Correção de perspectiva na resolução total da câmera, sem reduzir a imagem, com saída em JPEG qualidade 100.
7. Na hora de salvar, a pessoa escolhe **Imagens** (cada foto vira um item) ou **PDF** (todas as fotos da sessão viram um único PDF com várias páginas).
8. Arquivos na memória pública: imagens em `Pictures/Papyr` e PDFs em `Documents/Papyr`. Eles aparecem na galeria e no gerenciador de arquivos e continuam lá se o app for desinstalado.
9. Na lista Arquivos é possível **abrir/visualizar**, **compartilhar** e **excluir**.
10. Compartilhar também fica disponível na tela final do processo de salvar.
11. O recorte é definitivo: a foto original não é guardada e não dá para recortar de novo depois de salvo.
12. Dependências externas mínimas: apenas o pacote `camera`. Todo o resto é código do projeto, em Dart ou em Kotlin usando somente APIs do Android.

## 3. Fora do escopo

Sincronização com nuvem ou Google Drive, OCR, filtros (P&B, realce), renomear arquivos, recortar de novo depois de salvo, importar fotos da galeria, iOS, tablets e dobráveis abertos, PDF com senha, ícone personalizado, tradução dos textos internos do Material (o menu copiar/colar fica em inglês), cancelar um salvamento em andamento.

## 4. Decisões técnicas

| Tema | Decisão | Motivo |
|---|---|---|
| Dependências | `dependencies`: só `camera: ^0.12.1`. O `pubspec.lock` fixa `camera_android_camerax` 0.7.5+1, que tem a correção do `ResolutionPreset.max` (0.7.4+3+). `dev_dependencies`: o `flutter_lints` do template, que só roda em desenvolvimento e não vai no APK. O `cupertino_icons` do template é removido. | Requisito 12. |
| minSdk | 30 (Android 11+, cerca de 87% dos aparelhos) | Salvar PDF em `Documents` via MediaStore no Android 10 não é documentado e não foi testado. |
| ABI | Só arm64-v8a, com `ndk { abiFilters.clear(); abiFilters += "arm64-v8a" }` | Sem esse filtro, o APK traz as libs do CameraX para armeabi-v7a mas não o `libflutter.so` dessa ABI, e trava ao abrir num aparelho 32-bit. |
| Orientação | App travado em retrato, e só para celulares | No Android 16 com targetSdk 36, a trava de orientação é ignorada em telas a partir de 600 dp. Tablets ficam fora do escopo (ver riscos). |
| Detecção ao vivo | Dart puro, num isolate de trabalho, sobre o canal Y já girado para retrato e reduzido para no máximo 320 px | Sem OpenCV. Algoritmo validado em imagens sintéticas (seção 7). |
| Perspectiva em resolução total | Kotlin: `ImageDecoder` (aplica o EXIF) + `Matrix.setPolyToPoly` + `Canvas.drawBitmap` + `Bitmap.compress(JPEG, 100)` | Testado no emulador nas 8 orientações EXIF. Uma página de 12 MP leva cerca de 0,35 s numa CPU de desktop. |
| PDF | Gerador próprio em Dart, página a página, embutindo o JPEG sem recompressão (`/DCTDecode`) | Sem pacote e sem perda. Validado com poppler e ghostscript, e renderizado pelo `PdfRenderer` no emulador. |
| Ver PDF | `android.graphics.pdf.PdfRenderer` via Kotlin | Já vem no Android. |
| Armazenamento | MediaStore via Kotlin, sem permissão de armazenamento | Testado no emulador: salvar, listar, excluir, nomes duplicados e reinstalação. |
| Índice dos arquivos | Nenhum banco: a lista é uma consulta ao MediaStore | Sem permissão, o MediaStore só devolve o que este app criou. |
| Acesso aos arquivos | Sempre pela URI `content://`, passando pelo Kotlin | Comportamento igual em todas as versões. |
| Compartilhar | Intent `ACTION_SEND` / `ACTION_SEND_MULTIPLE` com URI do MediaStore + `ClipData` + permissão de leitura | Testado: outro app, sem nenhuma permissão, conseguiu ler os arquivos. |
| Threads no Kotlin | `MethodChannel(..., messenger.makeBackgroundTaskQueue())`: uma fila em segundo plano que executa uma chamada por vez | Testado. Dispensa Executor e Handler, e serializa o `PdfRenderer`. |
| Estado | `ChangeNotifier` + `ListenableBuilder`. Dois singletons no nível do app: `library` (a lista) e `session` (a sessão de captura). | Os recursos do SDK bastam. |
| Barra de navegação | Widget próprio `SnakeBar` | Requisito 12. |
| Qualidade da captura | Sem `setJpegImageQuality`, ou seja, o padrão do CameraX (95) | Essa chamada reconfigura a câmera toda vez que o controller é recriado. A foto da câmera é só um intermediário: o `warp` regrava tudo em JPEG 100. |
| Textos | Português no código. Datas (`dd/MM/aaaa HH:mm`) e tamanhos (`12,3 MB`) formatados à mão. | Sem `intl` e sem `flutter_localizations`. |

## 5. Arquitetura

### 5.1 Estrutura de arquivos

```
lib/
  main.dart                  MaterialApp (Material 3), Scaffold raiz com SnakeBar,
                             PopScope raiz, corpo = [FilesScreen, CameraScreen, SettingsScreen][index]
  library.dart               singleton `library`: ChangeNotifier com a lista do MediaStore, refresh()
  native.dart                ponte tipada para o MethodChannel "papyr/native"
  format.dart                formatar data e tamanho, sanitizar nome
  widgets/snake_bar.dart     barra com indicador que estica
  scan/session.dart          singleton `session`: fotos capturadas (Photo)
  scan/camera_screen.dart    preview, contorno ao vivo, lanterna, disparo, faixa de miniaturas
  scan/luma.dart             canal Y → imagem cinza em retrato com no máximo 320 px
  scan/detector.dart         detecção do quadrilátero (Dart puro)
  scan/crop_screen.dart      editor de 4 cantos por foto
  scan/save_screen.dart      nome, Imagens|PDF, processamento, Salvo + Compartilhar
  pdf_writer.dart            gerador de PDF página a página
  files/files_screen.dart    lista e menu de cada item
  files/image_viewer.dart    InteractiveViewer
  files/pdf_viewer.dart      PageView de páginas renderizadas
  settings_screen.dart       espaço usado, pastas, versão, aviso
test/
  detector_test.dart
  pdf_writer_test.dart
  format_test.dart
android/app/src/main/kotlin/com/pedroalves/papyr/MainActivity.kt
```

### 5.2 Modelo da sessão (`scan/session.dart`)

```dart
final session = Session(); // vive enquanto o processo vive
class Photo {
  final String path;          // CAP*.jpg no cache
  List<double>? detected;     // 8 doubles; calculado uma vez no editor
  List<double>? corners;      // edição da pessoa; null = usar detected ou a imagem inteira
  int rotation = 0;           // 0/90/180/270, sentido horário
  String? savedUri;           // modo Imagens: já salva (para retomar depois de falha parcial)
}
class Session extends ChangeNotifier { final photos = <Photo>[]; add / removeAt / clear }
```

- A sessão fica **fora** das telas, então sobrevive a troca de aba e à ida e volta entre câmera e editor.
- Ela só termina em três casos: salvamento concluído, descarte confirmado ou morte do processo.
- Se o processo morrer, a sessão se perde e os arquivos `CAP*.jpg` são limpos na próxima abertura do app.

### 5.3 Contrato do MethodChannel `papyr/native`

Tudo fica em `MainActivity.kt`, usando só APIs do Android, num canal criado com `makeBackgroundTaskQueue()`. Cada chamada é envolvida em `try/catch (Throwable)` e responde **exatamente uma vez**.

Códigos de erro:

| Exceção | Código |
|---|---|
| `Fail(code)`, exceção própria | o código dela |
| `OutOfMemoryError` | `memory` |
| `FileNotFoundException` e `SecurityException` | `not_found` |
| `ImageDecoder.DecodeException` e `IOException` do `PdfRenderer` | `decode` |
| outros | `io` |

No Dart, os resultados chegam como `Map<Object?, Object?>` e são convertidos com `.cast<String, Object?>()`. Números vindos do Dart são lidos como `Number`, e não como `Double`.

| Método | Argumentos | Retorno | Observações |
|---|---|---|---|
| `cacheDir` | — | `String` | Diretório de cache do app. |
| `preview` | `path`, `maxSide` | `{bytes, width, height}` | Usa `ImageDecoder` com `ALLOCATOR_SOFTWARE` e `setTargetSize`. O EXIF já vem aplicado: `info.size` é o tamanho de pé em resolução total, devolvido em `width`/`height`. Os bytes são um JPEG 90 reduzido. |
| `warp` | `path`, `corners` (8 doubles 0..1 no espaço de pé, ordem TL,TR,BR,BL), `rotation` | `{path, width, height}` | Ver 5.4. Gera `papyr_w_<n>.jpg` no cache. `width`/`height` são medidos **depois** da rotação. |
| `save` | `path`, `name`, `mime` | `{uri, name, size, date}` | Faz `insert` em `MediaStore.Images` (`image/jpeg`, `RELATIVE_PATH=Pictures/Papyr`) ou em `MediaStore.Files` (`application/pdf`, `RELATIVE_PATH=Documents/Papyr`), sempre em `VOLUME_EXTERNAL_PRIMARY`, com `IS_PENDING=1`. Copia com buffer de 64 KB, muda para `IS_PENDING=0` e consulta a linha de volta. Devolve o **nome real**, porque o MediaStore renomeia duplicatas para "x (1).jpg". Se falhar, apaga a linha. `date` em ms. |
| `list` | — | `[{uri, name, mime, size, date}]` | Uma consulta em `MediaStore.Files` com `relative_path IN ('Pictures/Papyr/','Documents/Papyr/')` (com barra no final), ordenada por `date_added DESC, _id DESC`. A URI é reconstruída com `ContentUris.withAppendedId` na coleção Images (jpeg) ou Files (pdf). `date = date_added * 1000`. Linhas pendentes ficam de fora. |
| `delete` | `uri` | — | `ContentResolver.delete`. Uma `SecurityException` (item que já sumiu) vira `not_found`. |
| `read` | `uri` | `bytes` | Bytes completos, para o visualizador de imagem. |
| `thumbnail` | `uri`, `mime`, `size` | `bytes` | Imagem: `loadThumbnail(Size(size, size))`. O resultado pode passar de `size` em um dos eixos, então o Dart exibe com `BoxFit.cover`. PDF: página 1 pelo `PdfRenderer`, com bitmap preenchido de branco. |
| `pdfInfo` | `uri` | `pageCount` | |
| `pdfPage` | `uri`, `index`, `width` (int, px) | `bytes` | Bitmap de `width × width*h/w` preenchido de branco, `render(RENDER_MODE_FOR_DISPLAY)`, JPEG 90. |
| `share` | `uris`, `mime` | — | Usa `ACTION_SEND` para 1 URI e `ACTION_SEND_MULTIPLE` para várias, com `EXTRA_STREAM`, `ClipData` com todas as URIs, `FLAG_GRANT_READ_URI_PERMISSION` e `createChooser`. Quando há imagem e PDF juntos, o mime é `*/*`. |
| `openAppSettings` | — | — | `ACTION_APPLICATION_DETAILS_SETTINGS`. |
| `appVersion` | — | `String` | `versionName`. |
| `cleanCache` | — | — | Apaga do cache os arquivos `CAP*.jpg` e `papyr_*`. É chamado **só** em três momentos: na abertura do app (cold start), depois de um salvamento concluído e depois de um descarte de sessão. Nunca ao retomar o app, porque a sessão em memória aponta para esses arquivos. |

### 5.4 `warp` em detalhe (testado no emulador)

1. `ImageDecoder.decodeBitmap(createSource(File(path)))` com `ALLOCATOR_SOFTWARE`. O bitmap já vem de pé. `HARDWARE` não serve porque não pode ser desenhado num `Canvas` de software.
2. Cada canto em pixels é `p[i] = corners[i] × (W ou H)`. A largura de saída é `max(|TL−TR|, |BL−BR|)` e a altura é `max(|TL−BL|, |TR−BR|)`, arredondadas, com mínimo 1.
3. `m.setPolyToPoly(p, 0, retângulo de saída, 0, 4)`. Se devolver `false`, o erro é `decode` (cantos degenerados).
4. A rotação vai na **mesma** matriz, para não criar um terceiro bitmap: `setRotate(rotation)`, depois `postTranslate(-bounds.left, -bounds.top)`, depois `m.postConcat(rot)`.
5. Cria o bitmap de saída ARGB_8888, faz `drawColor(WHITE)`, depois `drawBitmap(src, m, Paint(FILTER_BITMAP_FLAG))`, chama `src.recycle()` e grava com `compress(JPEG, 100)` num stream com buffer de 64 KB. Os dois bitmaps são reciclados num `finally`.
6. O pico de memória é `(srcW·srcH + outW·outH) × 4` bytes. Medido: +70 MB para recortar uma folha de 12 MP e +92 MB para a imagem inteira. Esse JPEG de saída é SOF0 baseline com 3 componentes e sem EXIF.

### 5.5 Manifest e build

- `xmlns:tools` na tag `<manifest>`. O template não traz, e sem ele o merge do manifest falha.
- `RECORD_AUDIO` e `WRITE_EXTERNAL_STORAGE` removidas com `tools:node="remove"`. São as que o plugin injeta.
- O `CAMERA` e o `uses-feature camera.any` do plugin ficam.
- Sem `INTERNET` no manifest principal.
- Na activity: `android:screenOrientation="portrait"` e label "Papyr".
- `android/app/build.gradle.kts`: `minSdk = 30` e o filtro de ABI arm64.
- `gradle.properties`:
  - `org.gradle.jvmargs=-Xmx3G -XX:MaxMetaspaceSize=1G` (o template vem com 8G, e esta máquina já travou com builds em paralelo);
  - `kotlin.daemon.jvmargs=-Xmx1536m`;
  - `android.builtInKotlin=false` e `android.newDsl=false`, como no template.
- Nunca rodar dois builds ao mesmo tempo.

## 6. Fluxos

### 6.1 Navegação e "voltar"

- A `SnakeBar` fica sempre montada no Scaffold raiz. O corpo é `[FilesScreen, CameraScreen, SettingsScreen][index]`, sem `IndexedStack`. Trocar de aba destrói a tela da câmera, mas a `session` continua intacta.
- O editor, a tela de salvar e os visualizadores são rotas no Navigator raiz, empilhadas sobre a barra.
- O voltar do Scaffold raiz é tratado num **único** `PopScope` com `canPop: index == 0`:
  - em Ajustes, ou em Escanear com a sessão vazia, vai para Arquivos;
  - em Escanear com fotos, pede "Descartar N fotos?". Se confirmado, faz `session.clear()` + `cleanCache` e vai para Arquivos.
- No editor, voltar retorna à câmera e mantém a sessão (dá para tirar mais fotos, e os cantos já editados ficam guardados).
- Na tela de salvar:
  - antes de salvar, voltar retorna ao editor;
  - durante o processamento, o voltar é ignorado;
  - depois do sucesso, voltar faz o mesmo que "Concluir".
- Toques repetidos em "Concluir" e "Continuar" são bloqueados, para não empilhar a mesma rota duas vezes.

### 6.2 SnakeBar

- 3 itens com ícone. O selecionado também mostra o rótulo.
- O indicador tem duas bordas animadas com curvas defasadas: a borda da frente se move primeiro e a de trás vem depois. Isso faz o indicador esticar e depois encolher. Um `AnimationController` de cerca de 400 ms.
- Soma `MediaQuery.viewPaddingOf(context).bottom` no espaçamento de baixo, porque o targetSdk 36 força o modo edge-to-edge.
- Cada item tem `Semantics(button: true, selected: ..., label: ...)`.

### 6.3 Câmera (aba Escanear)

1. **Criação**, serializada por uma corrente global `Future<void> _cameraGate`: sempre aguarda o `dispose` anterior antes de criar outro controller, porque o plugin é um singleton e um `dispose` atrasado desliga a câmera nova.
   - `CameraController(traseira, ResolutionPreset.max, enableAudio: false, imageFormatGroup: ImageFormatGroup.yuv420)`, depois `initialize()`, `lockCaptureOrientation(portraitUp)`, `setFlashMode(off)` e, se a lanterna estiver ligada, `setFlashMode(torch)`. Por último, `startImageStream`.
   - A ordem off → torch é **obrigatória**: o plugin guarda o estado da lanterna entre controllers.
   - Depois de cada `await`, confere `mounted` e se o controller ainda é o atual.
2. **Layout:**
   - `AnnotatedRegion(SystemUiOverlayStyle.light)`, fundo preto, `SafeArea` no topo;
   - `ColoredBox(preto) > Center > CameraPreview(c, child: CustomPaint(QuadPainter(quad)))`. O `Center` dá restrições folgadas, então o preview mantém a proporção dele (não fixar 3:4). O child fica fora da rotação, e os cantos normalizados são multiplicados direto pelo tamanho do child.
   - Embaixo: lanterna, disparo, faixa de miniaturas com contador e o botão "Concluir (n)".
3. **Detecção ao vivo:**
   - O stream é contínuo, com uma flag de ocupado. Frames de outro controller, frames durante uma captura e frames com o detector ocupado são descartados.
   - O `scan/luma.dart` lê o plano Y direto, sem copiar o plano inteiro. Monta uma imagem cinza **já em retrato** (rotação conforme `sensorOrientation`) com no máximo 320 px no lado maior, usando a média de 2×2 em cada ponto.
   - O frame é validado com `bytes.length ≥ (h−1)·bytesPerRow + w`, porque a última linha não tem padding.
   - Largura e altura são lidas de cada frame.
   - A imagem vai para um isolate de trabalho, criado no `initState` e encerrado no `dispose`, com `SendPort.send` simples. O isolate devolve 8 doubles ou null.
4. **Suavização:** antes da média exponencial (α = 0,5), os cantos novos são girados ciclicamente para o alinhamento de menor distância em relação aos anteriores. O contorno some depois de 5 frames seguidos sem detecção.
5. **Lanterna:** só alterna entre off e torch, sem modo auto e sem flash no disparo. O estado vale enquanto o app estiver aberto. Em aparelho sem flash, falha em silêncio.
6. **Disparo:**
   - O botão fica desabilitado enquanto `isTakingPicture`.
   - `takePicture()` gera o `CAP*.jpg`, que entra com `session.add`. A tela pisca rapidamente como sinal de captura.
   - As miniaturas vêm de `preview(path, 256)`. Dá para remover uma foto pela faixa.
   - Se der erro, aparece a snackbar "Falha ao capturar" e a sessão fica como estava.
7. **"Concluir (n)"** fica desabilitado com n = 0. Antes de abrir o editor, a câmera é parada: o preview sai da árvore, depois vem o `dispose`, e com isso a lanterna e o stream desligam. A câmera volta quando o `push` retorna, se a aba ainda estiver ativa.
8. **Ciclo de vida:**
   - O controller é descartado em `hidden`/`paused`, e **não** em `inactive`. O diálogo de permissão, a cortina de notificações e o menu de compartilhar só disparam `inactive`.
   - Em `resumed`, a câmera é recriada só se a aba estiver visível e a rota do topo for a raiz (`ModalRoute.isCurrent`).
   - Sempre tira o `CameraPreview` da árvore antes de chamar `dispose`.
9. **Erros:**
   - `CameraAccessDenied` mostra uma mensagem com "Tentar novamente" e "Abrir ajustes". O `resumed` só tenta de novo se a pessoa tocou em "Abrir ajustes" (uma flag), para não abrir o diálogo de permissão duas vezes seguidas.
   - `CameraPermissionsRequestOngoing` é ignorado.
   - Câmera ocupada ou bloqueada aparece em `value.errorDescription`, na mesma tela de mensagem, só com "Tentar novamente".
10. **Estados:** "Abrindo câmera…" (um indicador de carregamento) até o primeiro frame.

### 6.4 Editor de recorte

- `PageView` com as fotos da sessão e o indicador "2 de 5", que fica escondido quando há uma foto só.
- Para cada foto, `preview(path, 1600)` mostra um indicador de carregamento enquanto decodifica. Se falhar, a página vira um bloco de erro com o botão "Remover".
- **Detecção, uma vez por foto**, guardada em `photo.detected`. A prévia é decodificada com `ui.instantiateImageCodec`, usando `targetHeight: 320` quando a imagem é mais alta que larga e `targetWidth: 320` no caso contrário. Depois vira tons de cinza e passa pelo detector via `Isolate.run`.
- Os cantos editados ficam em `photo.corners`, separados dos detectados, para que reconstruir a página do `PageView` não apague a edição da pessoa.
- O padrão é `corners ?? detected ?? imagem inteira`.
- **Alças:**
  - 4 alças de 48 dp, com a imagem recuada para que dê para pegar as alças nas bordas;
  - linhas ligando os cantos;
  - o `RawMagnifier` mostra o canto enquanto ele é arrastado;
  - cantos limitados a 0..1;
  - um arrasto que deixaria o quadrilátero não convexo é recusado.
- **Botões:**
  - **Girar 90°** soma 90 a `rotation`, no sentido horário. A imagem e as alças aparecem giradas na tela (`RotatedBox`), e os cantos continuam guardados no espaço de pé original.
  - **Redefinir** volta para `detected` ou, se não houver, para a imagem inteira.
  - **Remover foto**: quando remove a última, volta para a câmera com a sessão vazia.
- "Continuar" abre a tela de salvar.

### 6.5 Salvar

1. **Nome:**
   - padrão `Papyr_aaaaMMdd_HHmmss`;
   - campo com `maxLength` de 100;
   - a sanitização (em `format.dart`) remove `\ / : * ? " < > |` e caracteres de controle, apara espaços e tira pontos do começo;
   - se o resultado ficar vazio, usa o nome padrão.
2. **Imagens | PDF:** começa em PDF com mais de uma foto e em Imagens com uma só. O seletor trava depois de um salvamento parcial.
3. **Processamento**, com o voltar ignorado. O progresso aparece como "Processando 2/5" e, no fim, "Gravando PDF…".
   - **Imagens**: para cada foto ainda sem `savedUri`:
     1. `warp`;
     2. `save(tmp, nome, "image/jpeg")`, com nome `<nome>_01.jpg`, `_02`… ou `<nome>.jpg` se for uma foto só;
     3. `photo.savedUri = uri`;
     4. apaga o temporário.
   - **PDF**:
     1. `cacheDir` + `papyr_out.pdf`, e `PdfWriter.open(caminho, pageCount: n)`;
     2. para cada foto, `warp`, depois `addPage(tmp)`, depois apaga o temporário;
     3. `close()`;
     4. `save(pdf, "<nome>.pdf", "application/pdf")`;
     5. apaga o temporário.
   - Os temporários são sempre apagados assim que usados, porque o pico em disco seria cerca de 3 vezes o tamanho final.
   - Vale sempre o `name` e a `uri` devolvidos pelo `save`.
4. **Sucesso:**
   - antes de mostrar a tela, faz `session.clear()` + `cleanCache` e guarda as URIs salvas no estado da tela;
   - a tela mostra "Salvo" com **Compartilhar** (`share` das URIs) e **Concluir**;
   - "Concluir" e o voltar fazem `popUntil(primeira)`, mudam a aba para Arquivos e chamam `library.refresh()`;
   - abrir Escanear de novo mostra uma câmera vazia.
5. **Erro:**
   - a sessão é mantida, a mensagem aparece e "Tentar de novo" fica disponível;
   - no modo Imagens, retoma da primeira foto sem `savedUri` e informa "N de M salvas". Compartilhar inclui todas as URIs já salvas;
   - erro `memory` não se resolve tentando de novo, e o requisito 6 proíbe reduzir a imagem. A mensagem sugere remover aquela foto.

### 6.6 Arquivos

- Lista em ordem de data decrescente. Cada linha tem:
  - miniatura (`thumbnail`, com `BoxFit.cover` e cache em memória por URI). O `ListView.builder` só pede miniaturas das linhas visíveis, e respostas de linhas que já saíram da tela são ignoradas;
  - nome;
  - selo IMG ou PDF;
  - data;
  - tamanho.
- Estados:
  - carregamento inicial;
  - lista vazia, com um botão "Escanear" que leva à aba;
  - erro ao carregar, com "Tentar de novo".
- **Interação:**
  - tocar abre o visualizador;
  - o menu ⋮ tem **Compartilhar** e **Excluir** (com confirmação);
  - a lista é atualizada ao puxar para baixo, quando o app volta para o primeiro plano, depois de salvar e depois de excluir.
- **Visualizador de imagem:**
  - `read(uri)`, depois `Image.memory(bytes, cacheWidth: 4096)` dentro de um `InteractiveViewer`;
  - a barra superior tem Compartilhar e Excluir;
  - excluir pede confirmação, fecha o visualizador, atualiza a lista e mostra uma snackbar.
- **Visualizador de PDF:**
  - `pdfInfo` dá o número de páginas;
  - um `PageView` horizontal com indicador "3 / 20". Cada página é um `InteractiveViewer` com a imagem de `pdfPage(uri, i, (larguraDaTela × dpr).round())`, mostrando um indicador de carregamento enquanto renderiza;
  - o swipe do `PageView` fica desabilitado enquanto a página está com zoom;
  - a barra superior tem Compartilhar e Excluir.
- Se der `not_found` (item apagado por fora, inclusive com o visualizador aberto), aparece uma mensagem, o visualizador fecha e a lista é atualizada.

### 6.7 Ajustes

- Espaço usado: quantidade de imagens, quantidade de PDFs e total, calculados a partir de `library`.
- Onde os arquivos ficam: `Pictures/Papyr` e `Documents/Papyr`.
- Aviso: "Desinstalar o Papyr não apaga seus arquivos, mas eles deixam de aparecer na lista do app."
- Versão (`appVersion`).

## 7. Detector (`scan/detector.dart`)

**Entrada e saída.** A entrada é uma imagem cinza **em retrato** (`Uint8List`, no máximo 320 px no lado maior). A saída são 4 cantos normalizados `(x+0,5)/w` na ordem TL, TR, BR, BL, limitados a 0..1, ou null. As constantes ficam no topo do arquivo, e os valores abaixo foram calibrados em imagens sintéticas.

1. **Desfoque** separável com o kernel `[1,4,6,4,1]`.
2. **Canny:**
   - Sobel (magnitude L2, histograma de 1500 faixas sobre os pixels internos);
   - supressão de não-máximos com desempate assimétrico (`v > m[i+off] && v >= m[i−off]`);
   - **limiares:** `alto = max(25, 4 × mediana da magnitude)` e `baixo = 0,3 × alto`;
   - histerese com comparação estrita (>).
3. **Dilatação** 3×3, uma vez.
4. **Candidatos**, por dois caminhos:
   - (a) componentes 8-conexos de pixels de **borda**;
   - (b) componentes 4-conexos de pixels **que não são borda** (o interior da folha), cujo quadrilátero final é empurrado 2 px para fora (offset em esquadria).
   - Nos dois casos, componentes cuja caixa envolvente tem menos de 20% da imagem são descartados.
5. **Para cada componente:**
   - fecho convexo (monotone chain sobre o pixel mais à esquerda e o mais à direita de cada linha);
   - Douglas-Peucker fechado com epsilon de 1% a 5% do perímetro, em passos de 0,5%, até chegar a 4 pontos;
   - **canto cortado:** se o resultado tiver 5 pontos e 2 vizinhos estiverem na mesma borda do quadro, os dois são trocados pela interseção dos lados vizinhos, desde que ela fique além da borda e menos de 30% para fora;
   - área mínima de 20% da imagem.
6. **Validação por contraste:**
   - em cada lado, amostra 3 px para dentro e 3 px para fora, na imagem desfocada, ao longo dos 80% centrais do lado;
   - uma amostra conta se `|dentro − fora| ≥ 8`, com o sinal predominante;
   - cada lado que não está na borda do quadro precisa de suporte ≥ 0,6;
   - um lado é "de borda" quando as duas pontas estão a no máximo `max(3 px; 1,5%)` da mesma borda do quadro, ou quando tem menos de 8 amostras válidas;
   - mais de 2 lados de borda: o candidato é rejeitado.
7. **Escolha:** fica o candidato com a maior `área × suporte médio`.
8. **Ordenação:** mantém a ordem cíclica do fecho (área de shoelace positiva = TL→TR→BR→BL em coordenadas de imagem) e gira a lista para começar no vértice de menor `x+y`. Isso nunca repete um canto. A regra de soma/diferença foi descartada porque falha perto de 45°.

Desempenho medido (AOT, desktop, 320×240): alguns milissegundos por frame. Num celular de entrada a expectativa é de 3 a 6 vezes mais, ainda dentro da meta de ≥ 5 atualizações por segundo. Se a passagem pelas regiões pesar demais, o caminho (b) sozinho com offset de 2 px rendeu o mesmo nos testes.

## 8. Gerador de PDF (`pdf_writer.dart`)

**API:** `PdfWriter.open(String path, {required int pageCount})`, `Future<void> addPage(String jpegPath)` e `Future<void> close()`. O número de páginas é conhecido de antemão, então os `Kids` são escritos logo no início.

**Objetos:**
- 1 = Catalog;
- 2 = Pages (`/Kids [3 0 R 6 0 R …] /Count N`);
- para a página i (começando em 0), n = 3+3i: n = Page, n+1 = Contents, n+2 = Image.

Os objetos são escritos estritamente em ordem.

**Cabeçalho:** os bytes crus `%PDF-1.4\n%\xE2\xE3\xCF\xD3\n` (15 bytes), escritos com `sink.add`. Nunca `sink.write`, que faz UTF-8. Todo o resto passa por `ascii.encode`, e o contador de bytes é mantido à mão. O único fim de linha é LF.

**Dimensões e cor:** largura, altura e componentes vêm do marcador **SOF** do próprio JPEG (lendo os primeiros 64 KB; `jpegInfo` é exportado para teste), e não do chamador. O espaço de cor segue os componentes: 1 → `/DeviceGray`, 3 → `/DeviceRGB`, qualquer outro valor lança `FormatException`.

**Página:** `/MediaBox [0 0 595.28 H]` com `H = (595.28·h/w).toStringAsFixed(2)`. Conteúdo `q 595.28 0 0 H 0 0 cm /Im0 Do Q`, com a **mesma** string H.

**Imagem:** `<< /Type /XObject /Subtype /Image /Width w /Height h /ColorSpace cs /BitsPerComponent 8 /Filter /DCTDecode /Length len >>`. O JPEG é copiado com `addStream`, e o número de bytes copiados é conferido contra `len`. O LF antes de `endstream` não entra no `/Length`.

**xref:** a entrada 0 é `0000000000 65535 f ` + LF. Cada entrada tem exatamente 20 bytes (`%010d 00000 n ` + LF). Depois vêm o trailer `<< /Size 3+3N /Root 1 0 R >>`, o `startxref` e o `%%EOF`.

**Erros:** `sink.done.ignore()` logo depois do `openWrite()`. Em qualquer falha, fecha o sink, apaga o arquivo parcial (sem deixar essa limpeza esconder o erro original) e relança a exceção.

**Entrada:** só JPEGs vindos do `warp` (de pé, sem EXIF). Os visualizadores de PDF ignoram o EXIF dentro do `/DCTDecode`.

**Observação:** o `PdfRenderer` tolera xref errado, então os testes unitários são a única proteção para visualizadores externos mais rígidos.

## 9. Tratamento de erros (resumo)

| Situação | Comportamento |
|---|---|
| Permissão de câmera negada | Mensagem com "Tentar novamente" e "Abrir ajustes". Só tenta de novo no `resumed` depois de "Abrir ajustes". |
| Câmera ocupada ou bloqueada | Mensagem com "Tentar novamente". |
| Falha ao tirar foto | Snackbar "Falha ao capturar". A sessão é mantida. |
| Folha não detectada | Sem contorno. A foto pode ser tirada mesmo assim, e o editor começa com a imagem inteira. |
| Prévia não decodifica | Bloco de erro na página do editor com "Remover". |
| `warp` com `decode`/`io` | Mensagem e "Tentar de novo". A sessão é mantida. |
| `warp` com `memory` | Mensagem sugerindo remover a foto (não dá para reduzir a imagem). |
| Disco cheio | Mensagem. Arquivo parcial e linha pendente são apagados. |
| Salvamento parcial (Imagens) | "N de M salvas". Tentar de novo retoma de onde parou. |
| Item sumiu por fora | `not_found`: mensagem, fecha o visualizador se estiver aberto e atualiza a lista. |
| Voltar com sessão | Confirmação de descarte só na câmera (o voltar raiz). O editor volta para a câmera. |
| App encerrado no meio da sessão | A sessão se perde. Os `CAP*` são limpos na próxima abertura. Uma linha pendente do MediaStore expira sozinha. |

## 10. Testes

**Unitários** (`flutter test`, usando `test()` e não `testWidgets()` quando há I/O real):

- **`detector_test.dart`**, com imagens sintéticas geradas no próprio teste. Tolerância de 3% nos cantos. A mediana medida foi de 0,4 a 0,6%. Casos:
  - folha clara em perspectiva com "linhas de texto";
  - baixo contraste;
  - folha branca em mesa clara com gradiente de luz;
  - fundo poluído encostando na folha;
  - folha encostando na borda;
  - canto cortado pelo quadro;
  - 4 cantos distintos com a folha girada uns 45°;
  - **sem folha (ruído, textura, gradiente): deve dar null**.
- **`pdf_writer_test.dart`:**
  - `jpegInfo` de um JPEG real de 1×1 (constante base64, 287 bytes);
  - com 3 páginas (RGB 1×1, RGB 40×400 e cinza 64×48 falsos):
    - o cabeçalho com a linha binária;
    - `startxref` aponta para `xref`;
    - contagem de entradas igual a 3+3N;
    - entrada 0 exata;
    - toda entrada tem 20 bytes e aponta para `k 0 obj`;
    - trailer `/Size` correto;
    - todo `/Length` bate com o tamanho do stream;
    - os bytes do JPEG aparecem intactos;
    - `MediaBox` de página não quadrada;
    - `/DeviceGray` para o JPEG de 1 componente;
  - erros que lançam exceção e não deixam arquivo: JPEG CMYK, entrada inexistente e diretório de saída inexistente.
- **`format_test.dart`:** sanitização de nome (caracteres proibidos, pontos no começo, vazio, acentos) e formatação de data e tamanho.

**Checklist manual**, no APK **release**, num aparelho real:

- [ ] o manifest final (`aapt2 dump permissions`) tem só `CAMERA`, sem `INTERNET` e sem `RECORD_AUDIO`; o APK tem só `lib/arm64-v8a`;
- [ ] primeira abertura: conceder a permissão faz o preview aparecer; negar uma vez pede só uma vez; "Abrir ajustes" e voltar funciona;
- [ ] a resolução da foto capturada é a máxima do sensor (log); o tamanho do frame de análise é logado e a proporção dele bate com a do preview;
- [ ] o contorno fica alinhado com a folha e atualiza ≥ 5 vezes por segundo num aparelho de entrada;
- [ ] a lanterna fica acesa durante a foto, inclusive depois de trocar de aba e de voltar do editor;
- [ ] várias fotos; trocar de aba no meio da sessão e voltar sem perder nada; voltar na câmera com fotos pede confirmação;
- [ ] editor: cantos, Girar 90°, Redefinir, remover a última foto;
- [ ] `warp` em ≤ 3 s por página num aparelho de entrada; as dimensões de saída estão corretas;
- [ ] salvar Imagens e PDF; nomes longos e com acento; nome duplicado vira "(1)";
- [ ] o PDF abre no app e num app externo (20 páginas);
- [ ] compartilhar no WhatsApp e no Gmail, inclusive várias imagens; compartilhar e depois voltar na tela "Salvo";
- [ ] excluir pela lista e pelo visualizador; apagar um arquivo pela galeria some da lista;
- [ ] retomar depois de uma falha parcial;
- [ ] voltar preditivo (Android 16) em cada tela.

## 11. Riscos conhecidos

- **Resolução sem plano B:** se o `ResolutionPreset.max` falhar num aparelho, o plugin `camera` não tem outra opção em resolução total (os outros presets são 16:9 e limitados). Testar em aparelhos reais.
- **Robustez do detector:** foi validado só em imagens sintéticas. Sombras cruzando a folha e reflexos ainda não foram testados. O editor manual cobre as falhas, e as constantes ficam expostas para calibrar.
- **Tamanho dos arquivos:** em 12 MP com JPEG 100, cada página fica com cerca de 3 a 15 MB, conforme o conteúdo. Um PDF de 20 páginas pode passar de 200 MB, e e-mail ou mensageiro podem recusar.
- **Memória:** um sensor acima de 12 MP pode gerar fotos maiores (por exemplo 50 MP, com cerca de 400 MB no `warp`). As fotos são processadas uma de cada vez, e um `OutOfMemoryError` vira o erro `memory`, sem redução de imagem.
- **Reinstalação:** depois de desinstalar e reinstalar, a lista começa vazia (o app perde a posse dos arquivos; verificado). O mesmo acontece se o banco de mídia do Android for reconstruído. Pedir `READ_MEDIA_IMAGES` não é permitido pela política da Play Store para um scanner. Limitação aceita.
- **Chave de assinatura:** se a chave mudar, é preciso desinstalar, e a lista se perde (ver acima). O release usa a chave de debug desta máquina (`~/.android/debug.keystore`). Para distribuir, criar um keystore fixo antes da primeira instalação definitiva.
- **Tablets e dobráveis:** no Android 16 com targetSdk 36, a trava de retrato é ignorada em telas a partir de 600 dp, e o contorno da câmera fica desalinhado. Fora do escopo (celulares apenas).
- **Custo do stream:** o plugin copia os 3 planos YUV (cerca de 2 a 3 MB) para o Dart a cada frame, mesmo com o detector ocupado. Se houver travamentos num aparelho de entrada, a melhoria documentada é o modelo pull (parar e retomar o stream, que é barato). Não faz parte deste plano.
- **Plugin `camera` recente:** o CameraX 1.6 mudou de pilha interna, e regressões por fabricante são possíveis.

## 12. Build

1. `flutter create --org com.pedroalves --project-name papyr --platforms android .`
2. Remover `cupertino_icons` do `pubspec.yaml`. `flutter pub add camera`.
3. Ajustes Android da seção 5.5: manifest, `minSdk`, ABI e `gradle.properties`.
4. Release: `flutter build apk --release`. O filtro de ABI já limita a arm64.
5. Sem git por enquanto. O `pubspec.lock` fica no diretório e fixa as versões.
