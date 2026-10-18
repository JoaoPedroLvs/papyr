# Papyr — Identidade visual, ícone e splash

- Data: 2026-10-17
- Status: aguardando aprovação
- Base: o app descrito em `2026-10-17-papyr-scanner-design.md`. Este documento muda só a aparência e alguns textos. Os poucos pontos daquele spec que mudam estão na seção 10.

## 1. Intenção

O visual atual parece "feito por IA": tema Material padrão gerado a partir de uma semente verde-azulada (`0xFF00897B`), sem relação com a logo, e telas simples demais. O dono do app quer o jeito do app do Claude: calmo, fundo de papel, títulos com serifa, quase sem bordas e sem enfeites. Mas quer isso nas cores da logo do Papyr (`logo.jpeg`, na raiz do repo), que tem azul-marinho, cantos de enquadramento azul-claro e uma linha de leitura verde neon.

A logo também vira o ícone do app e a tela de abertura (splash). Hoje os dois são os padrões do Flutter.

## 2. Objetivos, não objetivos e anti-objetivos

**Objetivos**
- Dar uma identidade única ao app inteiro (Arquivos, câmera, editor de recorte, salvar, visualizadores, Ajustes, diálogos e avisos), seguindo a direção "Papel e tinta" da seção 4.
- Ícone adaptativo e splash com a logo sobre fundo azul-marinho.
- Ter modo claro e escuro, porque o app já segue o tema do sistema hoje.

**Não objetivos**
- Mudar o comportamento, os fluxos, o processamento de imagem, o armazenamento ou o PDF.
- Criar funções novas, como busca, renomear ou filtros.
- Animações decorativas.

**Anti-objetivos (o trabalho falha se acontecer, mesmo que funcione)**
- Continuar parecendo Material padrão, com o roxo ou o verde-azulado de semente, `ListTile` cinza, chips `IMG`/`PDF` e ícones cinza genéricos.
- Usar o laranja-barro do Claude ou o fundo creme dele no lugar das cores da logo. A direção B foi mostrada e recusada.
- Pôr texto embaixo dos ícones da barra.
- Mostrar a barra de navegação na câmera.
- Ícone ou splash borrados ou serrilhados: a logo tem que ficar nítida em todas as densidades.

## 3. Restrições (do spec original, continuam valendo)

- Android apenas, minSdk 30, só retrato, só celulares.
- 100% offline. As fontes vão dentro do APK, sem download em tempo de execução e sem permissão de internet.
- `dependencies`: só `camera`. Nada de `google_fonts`, `flutter_svg`, `flutter_launcher_icons` ou `flutter_native_splash`, nem em `dev_dependencies`. Ícone e splash são recursos Android escritos à mão ou gerados por um script do projeto.
- Textos em português, escritos no código. Datas formatadas à mão, sem `intl`.
- Os nomes acessíveis atuais continuam: `Tirar foto`, `Lanterna`, `Compartilhar`, `Excluir`, `Remover foto`.

## 4. Decisões do dono do app

Tomadas em cima de modelos visuais:

1. **Direção A, "Papel e tinta":** fundo cor de papel, títulos com serifa, texto azul-marinho, quase sem bordas. O azul-claro e o verde da logo aparecem pouco, só como destaque.
2. **Barra de baixo, opção 3, só ícones:** Arquivos à esquerda e Ajustes à direita, como ícones sem texto. Escanear é um botão grande no meio, quadrado com cantos bem arredondados, azul-marinho, com os cantos de enquadramento e a linha verde da logo. Ele sobe acima da linha da barra.
3. **Os três botões da barra igualmente espaçados** na largura (três colunas iguais, cada item centrado na sua).
4. **Ícone de Ajustes: engrenagem** (`Icons.settings_outlined`).
5. **Câmera em tela cheia, sem a barra.** Um X no canto de cima sai da câmera, com o mesmo comportamento do voltar (seção 7.3).
6. **Ajustes reformulado** como no modelo aprovado (seção 7.4).
7. **Ícone e splash com fundo azul-marinho** (`#102E50`), com a marca da logo no centro e, na splash, o nome "Papyr" no rodapé.

## 5. Sistema visual

### 5.1 Cores

As cores ficam definidas num lugar só (por exemplo `lib/theme.dart`), e o `ColorScheme` é montado à mão com elas. **Nada de `ColorScheme.fromSeed`.**

| Papel | Claro | Escuro ("tinta à noite") | Uso |
|---|---|---|---|
| fundo | `#F6F3EC` papel | `#0E1A2A` | fundo de todas as telas claras, barra de baixo, diálogos |
| folha | `#FFFFFF` | `#16263B` | miniaturas, superfícies elevadas |
| painel | `#EEE9DD` | `#1A2B42` | quadro de aviso, fundo dos campos de texto |
| pílula | `#E8E2D4` | `#1E3150` | destaque da aba ativa, trilho do medidor de espaço |
| linha | `#E6E1D6` | `#24364F` | linhas finas: topo da barra, divisórias |
| tinta | `#102E50` | `#F1EEE6` | texto principal, ícones ativos, botões cheios, botão Escanear |
| sobre a tinta | `#F6F3EC` | `#102E50` | texto e ícones em cima da tinta |
| cinza | `#6B655A` | `#A3ADBB` | texto secundário (data, tamanho, rótulos de seção) |
| inativo | `#8A8376` | `#7F8DA3` | ícones da barra fora de foco |
| céu | `#32B0FA` | `#32B0FA` | cantos de enquadramento da logo, parte "PDFs" do medidor, foco do teclado |
| verde | `#00FD9A` | `#00FD9A` | linha de leitura, contorno da folha na câmera e no editor. **Nunca como cor de texto sobre fundo claro.** |
| erro | `#B3261E` | `#F2B8B5` | ações destrutivas e mensagens de erro |

Telas de mídia (câmera, editor de recorte e visualizadores) são sempre escuras, nos dois temas, porque a foto precisa de contraste. A câmera usa preto puro. O editor e os visualizadores usam o fundo do tema escuro (`#0E1A2A`), com controles cor de papel.

**Como ler os nomes de cor nas seções 6 e 7:**
- Nas telas de mídia, "cor de papel" e "tinta" são valores fixos (`#F6F3EC` e `#102E50`), iguais nos dois temas.
- No resto do app, os nomes da tabela são papéis do tema e trocam de valor no escuro. Onde houver texto ou ícone sobre "tinta", a cor dele é sempre "sobre a tinta". Exemplos: SnackBar, segmento escolhido e botões cheios.

O contraste do texto secundário (`#6B655A` sobre `#F6F3EC`) fica perto de 5:1. `#7A7468`, usado no modelo, dava só 4,2:1 e foi escurecido.

### 5.2 Tipografia

- **Newsreader** (serifa, OFL), peso 500, nos títulos de tela, no título da lista vazia, nos títulos de diálogo e no "Salvo".
  - Tem eixo de tamanho óptico (opsz), e o **opsz é igual ao tamanho da letra** (34, 28 ou 22), como o Chrome fez nos modelos aprovados.
  - O Flutter não ajusta o opsz sozinho: sem `FontVariation('opsz', tamanho)` explícito, o texto sai no corte padrão de texto (opsz 18).
  - O `fontWeight` já controla o eixo de peso no Flutter 3.44.
- **Outfit** (sem serifa geométrica, parecida com o nome Papyr da logo, OFL) em todo o resto, nos pesos 400, 500, 600 e 700.
- Os dois arquivos de fonte ficam em `assets/fonts/` e são declarados em `pubspec.yaml`. A licença OFL fica junto e é registrada no `LicenseRegistry`.

Escala, em dp:

| Elemento | Fonte | Tamanho / altura de linha | Peso |
|---|---|---|---|
| título de tela ("Seus documentos", "Ajustes", "Salvar") | Newsreader | 34 / 1,05, espaçamento −0,01em | 500 |
| título da lista vazia, "Salvo" | Newsreader | 28 / 1,1 | 500 |
| título de diálogo | Newsreader | 22 / 1,2 | 500 |
| nome do arquivo, item de lista | Outfit | 15 / 1,3 | 500 |
| corpo | Outfit | 15 / 1,45 | 400 |
| detalhe (tipo, tamanho, hora, legenda) | Outfit | 12,5 / 1,3 | 400 |
| rótulo de seção ("Hoje", "Espaço usado") | Outfit | 13 / 1,3, em frase normal (nunca CAIXA ALTA) | 500 |
| botão | Outfit | 15 | 600 |

### 5.3 Forma

Os cantos arredondados seguem a hierarquia, e não um valor único para tudo:

- miniaturas: 4 dp, como uma folha;
- campos e painéis: 14 dp;
- botões, pílulas e o medidor: totalmente arredondados;
- botão Escanear: 21 dp num quadrado de 62 dp;
- diálogos: 24 dp;
- avisos (SnackBar): 14 dp, flutuantes.

Não há sombras, exceto embaixo do botão Escanear (difusa e azulada, `0 8 18 rgba(16,46,80,.3)`) e uma sombra leve nas folhas em cima de fundo escuro. Também não há gradientes decorativos.

### 5.4 Ícones

Ícones Material outlined do pacote que já vem no Flutter, como `folder_outlined`, `settings_outlined`, `share` e `delete_outline`. O botão Escanear e a marca da logo são desenhados por código (seção 9).

### 5.5 Movimento

Só movimento que responde a um toque:
- a pílula da aba ativa estica até a aba nova e encolhe atrás dela, o efeito "snake" que já existe;
- o retorno de toque padrão (ripple) nos botões.

Nada de animação de entrada nas telas. Com `MediaQuery.disableAnimations`, a pílula pula direto para o destino.

### 5.6 Barras do sistema

O app vai de ponta a ponta da tela. Nas telas claras, os ícones da barra de status ficam escuros. Na câmera, no editor e nos visualizadores, ficam claros. No tema escuro, ficam sempre claros.

## 6. Barra de navegação

Ela substitui a `SnakeBar` atual, seja reescrevendo o widget, seja trocando por outro. Pode continuar sendo um widget do projeto (requisito 12).

- **Altura:** 64 dp mais o recuo inferior do sistema, sem acréscimos. Fundo = cor de fundo. Linha fina no topo.
- **Layout:** três colunas iguais, com o item centrado em cada uma.
  - Esquerda: `Icons.folder_outlined`, 24 dp.
  - Meio: espaço vazio, embaixo do botão Escanear.
  - Direita: `Icons.settings_outlined`.
- **Área de toque das abas laterais:** a coluna inteira, na altura total da barra, como a `SnakeBar` faz hoje desde o commit `ef990b5`. A pílula de 64×44 é só visual. Assim a área passa do mínimo de 48 dp do Android e um toque perto da borda de baixo continua acertando.
- **Aba ativa:** pílula de 64×44, totalmente arredondada, na cor de pílula, com o ícone na cor de tinta. As outras abas ficam com o ícone na cor inativo. A pílula se move entre Arquivos e Ajustes com o efeito snake: a borda da frente vai primeiro e a de trás vem depois, como hoje.
- **Botão Escanear:** 62×62 dp, cantos de 21 dp, centrado na horizontal, com o topo 22 dp acima da linha do topo da barra.
  - **Fica no `Scaffold.floatingActionButton`**, com um `FloatingActionButtonLocation` próprio, e **não dentro da barra**. No Flutter, a parte de um filho que sai dos limites do pai não recebe toques, mesmo com `Clip.none`, então o topo do botão ficaria morto. No slot de FAB isso não acontece, e o Scaffold já põe os SnackBars flutuantes acima do botão.
  - **Tema claro:** fundo tinta `#102E50`, cantos de enquadramento papel `#F6F3EC` e linha verde `#00FD9A` com brilho.
  - **Tema escuro:** fundo `#1F3A5F`, um marinho mais claro que se destaca do fundo `#0E1A2A`, com os mesmos cantos papel e a mesma linha verde com brilho. *Não* use fundo papel no escuro: o verde sobre papel tem contraste de 1,17:1 e some.
  - Sombra: `0 8 18 rgba(16,46,80,.3)` no claro e `0 8 18 rgba(0,0,0,.4)` no escuro.
  - Dentro fica a variante "Escanear" da marca (seção 9), com uns 29 dp.
  - Tocar nele abre a aba Escanear.
- **Sem texto visível.** Cada item tem `Semantics(button: true, selected: …, label: 'Arquivos' | 'Escanear' | 'Ajustes')` e `tooltip` com o mesmo nome.
- **Na aba Escanear, a barra e o botão não aparecem** quando `tab.value == 1`:
  - `bottomNavigationBar` fica `null`;
  - `floatingActionButton` vira `SizedBox.shrink()`, e não `null`. Trocar `null` por widget dispara a animação de entrada do FAB, que encolhe, gira e ignora `disableAnimations`.
- **Conteúdo atrás do botão:** como o botão invade a área do conteúdo, as listas ganham 24 dp a mais de espaço no fim, para o último item não ficar escondido.

## 7. Telas

### 7.1 Arquivos

- **Sem AppBar.** O topo é parte do conteúdo rolável: a marca da logo pequena (30 dp) alinhada à esquerda, depois o título "Seus documentos" (Newsreader 34) e, embaixo, o resumo "4 arquivos, 9,8 MB" (singular "1 arquivo"). Margem lateral de 20 dp, tudo alinhado à esquerda.
- **Grupos por dia:** um rótulo de seção por dia, com os arquivos daquele dia embaixo. Os rótulos são "Hoje", "Ontem", "15 de outubro" e, em anos anteriores, "15 de outubro de 2025". Os nomes dos meses são escritos à mão, sem `intl`.
- **Linha de arquivo:**
  - miniatura em pé de 38×52 dp, cantos de 4 dp, contorno fino na cor de linha e imagem com `BoxFit.cover`;
  - enquanto carrega ou se falhar, aparece um retângulo cor de folha com o ícone do tipo bem discreto;
  - nome em Outfit 15/500, com reticências;
  - embaixo, o detalhe "PDF, 2,4 MB, 14:32" ou "Imagem, 3,1 MB, 10:15", só com a hora, porque o dia está no rótulo;
  - no fim, o menu ⋮ com Compartilhar e Excluir, como hoje;
  - **sem** os chips `IMG`/`PDF` e **sem** a linha "data · tamanho".
- Puxar para atualizar continua funcionando, com o indicador na cor de tinta.
- **Lista vazia:** a marca grande (120 dp), "Nada escaneado ainda" (Newsreader 28) e, embaixo, "Toque no botão do meio para fotografar sua primeira folha." (cinza, até 3 linhas, centralizado). **Não tem botão**: a ação é o botão Escanear da barra.
- **Erro ao carregar:** a mesma composição, com o título "Não foi possível carregar os arquivos." e um botão cheio "Tentar de novo".
- **Carregando a lista pela primeira vez:** indicador circular na cor de tinta, centralizado.

### 7.2 Ajustes

- Sem AppBar, com o título "Ajustes" (Newsreader 34) no topo do conteúdo, como em Arquivos.
- **Espaço usado:**
  - rótulo de seção "Espaço usado";
  - frase "**9,8 MB** em 12 imagens e 3 PDFs", com o tamanho em 600, no singular quando for o caso ("1 imagem", "1 PDF") e omitindo o tipo que estiver em zero ("2,5 MB em 3 PDFs");
  - medidor de 8 dp de altura, totalmente arredondado: trilho na cor de pílula, segmento de imagens na cor de tinta e segmento de PDFs na cor céu, proporcionais aos bytes;
  - legenda com um quadradinho de cada cor: "Imagens 6,1 MB" e "PDFs 3,7 MB".
  - Sem arquivos, a frase vira "Nada salvo ainda" e o medidor e a legenda somem.
- **Onde ficam os arquivos:** rótulo de seção e duas linhas.
  - Uma linha com ícone de imagem, "Imagens" e embaixo "Pictures/Papyr".
  - Outra com ícone de documento, "PDFs" e embaixo "Documents/Papyr".
  - As duas são separadas por uma linha fina e não são clicáveis.
- **Aviso:** quadro na cor de painel, cantos de 14 dp, ícone de informação pequeno e o texto "Desinstalar o Papyr não apaga seus arquivos, mas eles deixam de aparecer aqui." (12,5, cinza-escuro).
- **Rodapé**, empurrado para o fim da tela quando houver espaço:
  - a marca (32 dp);
  - o nome "Papyr" usando a imagem do nome extraída da logo (seção 8.4), tingida na cor de tinta;
  - "Versão 1.0.0" em cinza.
- A tela rola se não couber.

### 7.3 Escanear (câmera)

- Tela cheia, sem a barra. Fundo preto puro, e a câmera agora cuida do recuo inferior do sistema. Hoje o `SafeArea(bottom: false)` conta com a barra embaixo.
- **X no canto superior esquerdo**, sobre o preview: botão circular de 40 dp com fundo `rgba(0,0,0,.45)`, ícone branco e tooltip "Fechar". Ele faz exatamente o que o voltar do sistema faz na aba Escanear hoje:
  - sem fotos, vai para Arquivos;
  - com fotos, pergunta "Descartar N fotos?" e só sai se a pessoa confirmar.
  - A lógica de `_back` do `main.dart` passa a ser reaproveitável pelos dois caminhos.
- **Contorno da folha ao vivo:** cor verde `#00FD9A` com um brilho suave (o mesmo traço desenhado de novo, mais largo e com `MaskFilter.blur`).
- **Faixa de miniaturas:**
  - miniaturas em pé de 34×46 dp com cantos de 3 dp;
  - o botão de remover fica no canto, um círculo escuro pequeno com ×, mantendo a área de toque de 48 dp e o tooltip "Remover foto";
  - a contagem fica à direita: "1 foto" ou "N fotos", no lugar de "N foto(s)".
- **Controles**, numa grade de 3 colunas:
  - lanterna à esquerda: círculo de 44 dp com fundo `rgba(255,255,255,.08)` e tooltip "Lanterna";
  - disparador no centro: anel de 74 dp em cor de papel, com o disco interno também cor de papel e semântica "Tirar foto";
  - "Concluir (N)" à direita: pílula cor de papel com texto em tinta 600, que fica translúcida quando desabilitada.
- Os estados "Abrindo câmera…" e de erro de permissão continuam, com os botões no estilo novo.

### 7.4 Editor de recorte

- Fundo e AppBar no fundo escuro do tema (`#0E1A2A`), com texto cor de papel. O título "2 de 3" passa para Outfit 500.
- **Contorno e alças:**
  - contorno em verde `#00FD9A`, com preenchimento verde a 15% de opacidade;
  - alças com aro verde e miolo de papel a 30%;
  - a lupa ganha aro cor de papel.
- **Barra inferior:**
  - Girar 90°, Redefinir e Remover foto como botões de texto cor de papel, com ícone e texto, como hoje;
  - "Continuar" como botão cheio cor de papel com texto em tinta.

### 7.5 Salvar

- AppBar transparente, só com o voltar (na cor de tinta), seguida do título "Salvar" (Newsreader 34) no conteúdo.
- **Campo Nome:** preenchido na cor de painel, cantos de 14 dp, sem contorno e com foco na cor céu.
- **Escolha Imagens/PDF:** continua um `SegmentedButton`, com o tema novo. O segmento escolhido fica na cor de tinta com texto papel, e o outro, com contorno na cor de linha.
- "Salvar" é um botão cheio na cor de tinta, largura total, embaixo.
- **Processando:** indicador circular na cor de tinta e o texto de status em Outfit.
- **Pronto:** a marca no lugar do ícone de check, depois "Salvo" (Newsreader 28). Embaixo, "Compartilhar" (botão cheio na cor de tinta) e "Concluir" (contorno).
- **Erro:** ícone de erro na cor de erro e a mensagem atual. Os botões seguem o estilo novo.

### 7.6 Visualizadores (imagem e PDF)

- Fundo `#0E1A2A`, AppBar do mesmo fundo com o nome do arquivo em Outfit 500 cor de papel, e as ações Compartilhar e Excluir como hoje.
- **PDF:** o contador "2 / 5" vira uma pílula escura translúcida com texto cor de papel em Outfit 500.

### 7.7 Diálogos e avisos

- **Diálogos** ("Excluir arquivo?", "Descartar N fotos?"):
  - fundo na cor de fundo, cantos de 24 dp, título em Newsreader 22;
  - "Cancelar" em texto na cor de tinta;
  - a ação destrutiva ("Excluir", "Descartar") em texto na cor de erro.
- **SnackBar:** flutuante, fundo na cor de tinta, texto cor de papel e cantos de 14 dp.
- **Menu ⋮:** fundo na cor de folha e cantos de 14 dp. A opção "Excluir" fica na cor de erro.

## 8. Ícone e splash

### 8.1 Origem e gerador

A marca é redesenhada em vetor a partir de `logo.jpeg` (geometria no apêndice A). O JPEG original tem fundo branco, por isso não serve direto.

**Tudo no Android é vetor**, menos o nome "Papyr":
- ícone (camada da frente e camada monocromática);
- splash do Android 12+;
- splash do Android 11.

São VectorDrawables gerados a partir da geometria, então ficam nítidos em qualquer densidade e não há PNG de ícone por densidade.

**O brilho:** o VectorDrawable não tem desfoque. Nos recursos do Android, o brilho da linha verde é imitado com gradientes, duas camadas atrás da linha:
- um `radialGradient` (verde com 70% de opacidade até transparente) num círculo dentro de um `<group>` achatado na vertical (`scaleY` perto de 0,12), que vira uma elipse que se apaga nas pontas;
- uma faixa com `linearGradient` vertical (transparente, verde a 55% e transparente), um pouco mais curta que a linha.

Isso deve ficar visualmente parecido com o desfoque gaussiano do apêndice A. Confira lado a lado com a referência rasterizada (veja abaixo).

Um script do projeto (por exemplo `tool/brand.py`, em Python 3 com Pillow, que já está instalado) gera, a partir da geometria:
- os XMLs de vetor;
- os PNGs do nome;
- um SVG de referência com o desfoque de verdade.

O SVG é rasterizado com `google-chrome --headless --screenshot --default-background-color=00000000`, que existe nesta máquina, só para comparar e gerar as prévias de máscara. Os arquivos gerados são versionados.

**Entrada do nome:** `assets/brand/wordmark.png` (seção 8.4), versionado. O `logo.jpeg` **não** vai para o git (1 MB) e **não** é mexido: continua sem versionar na raiz. O gerador só precisa dele para refazer o `wordmark.png`, e recebe o caminho como argumento.

### 8.2 Ícone adaptativo (`android/app/src/main/res`)

- `mipmap-anydpi-v26/ic_launcher.xml`, com três camadas:
  - `background` = `@color/ic_launcher_background` (`#102E50`);
  - `foreground` = `@drawable/ic_launcher_foreground`;
  - `monochrome` = `@drawable/ic_launcher_monochrome`.
- `drawable/ic_launcher_foreground.xml`: VectorDrawable de 108×108 dp com a marca completa e colorida (cantos azul-claros, folha branca com contorno marinho, dobra, sombra leve e linha verde com brilho em gradiente), sobre fundo transparente, centralizada.
  - A largura externa dos cantos de enquadramento ocupa **47 dp** do quadro de 108 dp.
  - **Nada pode sair da zona segura**, o círculo de 66 dp. Confira gerando a prévia com máscara circular e com máscara de "squircle".
  - O ponto mais longe do centro é a borda externa da curva dos cantos, a 670 unidades do apêndice A para 977 de largura. Com 47 dp, ele fica a uns 32,2 dp do centro, dentro dos 33 dp da zona segura. **Não aumente a marca.**
- `drawable/ic_launcher_monochrome.xml`: a mesma geometria e escala, numa cor só (`#000000`, o sistema tinge), só com traços (cantos, contorno da folha, dobra e linha), sem preenchimento da folha e sem brilho.
- **Os `mipmap-*/ic_launcher.png` antigos são apagados**: com minSdk 30, o Android sempre usa o ícone adaptativo e eles nunca são lidos. O manifest continua com `android:icon="@mipmap/ic_launcher"`.

### 8.3 Splash

**Tamanho igual em todas as versões:** a marca aparece com **136 dp** de largura externa dos cantos de enquadramento, centralizada. O ponto mais longe fica a uns 93 dp do centro, então cabe no círculo de 192 dp (raio 96) da splash do Android 12+, perto do maior tamanho possível.

O nome fica num quadro de 200×80 dp com a base 60 dp acima da borda de baixo. É onde o Android 12+ põe a imagem de marca, e o Android 11 copia essa posição.

**Android 12 ou mais novo (API 31+)**, com a SplashScreen do sistema:
- crie `values-v31/styles.xml` **e** `values-night-v31/styles.xml`. O qualificador `night` tem precedência sobre `v31`, então sem o segundo o tema escuro cai no `values-night` antigo;
- `LaunchTheme` com:
  - `android:windowSplashScreenBackground` = `#102E50`;
  - `android:windowSplashScreenAnimatedIcon` = `@drawable/splash_icon`;
  - `android:windowSplashScreenAnimationDuration` = um valor curto (por exemplo 200). No Android 12/12L ele é necessário para a splash usar o ícone animado;
  - `android:windowSplashScreenBrandingImage` = `@drawable/splash_branding`.
- **Por que precisa de `splash_icon`:**
  - Sem ele, o sistema desenha só a camada da frente do ícone e passa por uma rasterização num bitmap de 108 dp, depois ampliado umas 1,8 vezes. A marca sairia borrada, que é um dos anti-objetivos, e do tamanho errado.
  - Um drawable estático também passa por esse caminho.
  - Só um drawable *Animatable* é desenhado direto no tamanho final. Isso foi conferido no código do AOSP: `SplashscreenContentDrawer`, `SplashscreenIconDrawableFactory`.
- **`drawable/splash_icon.xml`:**
  - é um `animated-vector` que embrulha um VectorDrawable de 288×288 dp com a marca a 136 dp, centralizada e dentro do círculo de 192 dp;
  - tem uma animação que não muda nada visível (por exemplo `alpha` de 1 para 1), só para ser Animatable.
- **`splash_branding`:** o nome em cor de papel `#F6F3EC`, centralizado no quadro de 200×80 dp, com uns 136 dp de largura. Gere PNGs para xhdpi, xxhdpi e xxxhdpi (400×160, 600×240 e 800×320 px). O sistema estica a imagem para o quadro, então o PNG precisa ter exatamente essa proporção.

**Android 11 (API 30)**, com a splash antiga do Flutter:
- Com minSdk 30, só o `drawable-v21/launch_background.xml` é lido. O `drawable/launch_background.xml` é código morto e **é apagado**. Os dois arquivos de hoje são diferentes: um usa `@android:color/white`, o outro usa `?android:colorBackground`.
- O `drawable-v21/launch_background.xml` vira uma `layer-list` com:
  - a cor `#102E50`;
  - a marca: um item com o mesmo VectorDrawable do `splash_icon` (a parte não animada), com `android:width`/`android:height` de 288 dp e `android:gravity="center"`. Assim a marca sai com os mesmos 136 dp;
  - o nome: um item com `@drawable/splash_branding`, com 200×80 dp, `android:gravity="bottom|center_horizontal"` e `android:bottom="60dp"`.

**Os dois casos:**
- `NormalTheme` (o fundo da janela entre a splash e o primeiro quadro do Flutter) passa a ser `#F6F3EC` no claro e `#0E1A2A` no escuro, e não branco nem preto, para não piscar.
- As cores ficam em `values/colors.xml`.

### 8.4 Nome "Papyr"

É extraído de `logo.jpeg` (a área do texto, mais ou menos `x 480–1570, y 1380–1790` no JPEG de 2048 px):
- método "cor para alfa" contra o branco: `alfa = (255 − L) / (255 − L_marinho)`, com `L_marinho ≈ 41`;
- corte de ruído abaixo de 10/255;
- recorte justo.

O resultado tem uns 982×305 px. Ele é guardado em `assets/brand/wordmark.png`, em branco com alfa, e é usado de três formas:
- **no app:** tingido em tempo de execução no rodapé de Ajustes, com `color` + `BlendMode.srcIn`;
- **no Android:** é a base do `splash_branding`, em cor de papel e com o quadro de 200×80 dp;
- **no gerador:** é a fonte para refazer os PNGs sem o JPEG.

## 9. A marca dentro do app

- Um `CustomPainter` (por exemplo `PapyrMark`) desenha a marca completa com a geometria do apêndice A, escalada para o tamanho pedido:
  - cantos na cor céu;
  - folha branca com contorno marinho e a sombra leve embaixo;
  - dobra;
  - linha verde com brilho, desenhada de novo mais larga e com `MaskFilter.blur`.
- Usado no topo de Arquivos (30 dp), na lista vazia (120 dp), no rodapé de Ajustes (32 dp) e em "Salvo" (72 dp).
- Fica igual nos dois temas: a folha branca com contorno marinho funciona sobre o papel e sobre o escuro.
- Uma variante "Escanear" desenha só os cantos e a linha, para o botão do meio da barra.
  - Os cantos ficam em papel `#F6F3EC` nos dois temas, já que o botão é sempre marinho (seção 6).
  - A linha fica verde `#00FD9A`, com brilho.
  - O painter recebe as cores como parâmetro, e não do tema.

## 10. O que muda no spec original

- Requisito 2: continua com 3 abas e o efeito snake, mas a barra agora é a da seção 6 (só ícones e Escanear destacado no meio) e some na câmera.
- Fora do escopo: "ícone personalizado" sai da lista e passa a fazer parte deste trabalho.
- Seção sobre a tela da câmera: o `SafeArea(bottom: false)` vira `true`, entra o X e mudam os estilos da seção 7.3. O ciclo de vida da câmera não muda.
- `Dependências`: continua só `camera`. As fontes são arquivos do projeto.

## 11. Testes

O comportamento não muda, mas vários testes procuram textos e widgets que mudam. Eles devem ser atualizados, sem remover a cobertura:

- `test/snake_bar_test.dart` ou o equivalente da barra nova:
  - continua checando que os ícones laterais ficam centrados na altura da barra (a caixa de 64 dp, sem o botão Escanear, que fica no slot de FAB);
  - o toque perto da borda de baixo da barra continua acertando, com o teste de hoje sem mudança;
  - tocar em cada item, inclusive no topo elevado do botão Escanear, muda a aba certa;
  - os rótulos semânticos existem;
  - as áreas de toque passam no `androidTapTargetGuideline`.
- `test/files_screen_test.dart`:
  - "Nenhum arquivo ainda" e o botão "Escanear" viram "Nada escaneado ainda", sem botão;
  - os chips `PDF`/`IMG` e "17/10/2026 14:05 · 12,3 MB" viram o detalhe novo ("PDF, 12,3 MB, 14:05") e o rótulo do grupo.
- `test/settings_screen_test.dart`: a frase de espaço, as pastas, o aviso e a versão nos textos novos.
- **Testes da câmera:**
  - Nenhum teste atual confere "N foto(s)". A contagem nova ("1 foto" ou "N fotos") e o X (com e sem fotos) entram como **testes novos**.
  - Montar uma `CameraScreen` de verdade esbarra no `_cameraGate`, que vale para o processo inteiro e não passa de um `testWidgets` para outro. Por isso esses testes:
    - ou ficam dentro do único `testWidgets` de `test/camera_lifecycle_test.dart`;
    - ou vão para um arquivo próprio;
    - ou testam o tratamento de voltar compartilhado (seção 7.3) sem montar a câmera.
- **Testes novos:**
  - rótulo de grupo por data (Hoje, Ontem, mesmo ano, outro ano);
  - frase de espaço com singular, plural e zero;
  - a barra some quando `tab.value == 1`.
- O que precisa de aparelho, como ícone, splash e fonte renderizada, é conferido com capturas de tela num emulador ou aparelho:
  - ícone com máscara circular e ícone temático;
  - splash no Android 12+ (nitidez das bordas da marca numa tela xxhdpi ou maior) e no 11, com a marca do mesmo tamanho nos dois;
  - as telas nos temas claro e escuro.

## 12. Deixado para quem for implementar

- A organização do código do tema (arquivo, nomes) e como a barra nova é implementada, desde que siga a seção 6.
- Arquivo variável ou instâncias estáticas das fontes, desde que pesos e tamanho óptico saiam como na seção 5.2.
- Ajustes finos de espaçamento de poucos dp.
- A ordem da lista já vem do MediaStore. Se não vier ordenada por data decrescente, ordene antes de agrupar.
- Os valores exatos dos gradientes que imitam o brilho nos VectorDrawables (seção 8.1), desde que, lado a lado com a referência desfocada, a diferença seja difícil de notar no tamanho real.

## 13. Referência visual

Os modelos aprovados ficaram em `.superpowers/brainstorm/158878-1792276985/content/` (fora do git):
- `direcao.html` (direção A);
- `telas-v3.html` (Arquivos, câmera e Ajustes);
- `icone-ajustes-v2.html` (opção 1, engrenagem);
- `icone-splash-v2.html` (opção 2, marinho).

Eles são aproximações em HTML. Este documento vale mais que os modelos.

## Apêndice A. Geometria da marca

Coordenadas no espaço do `logo.jpeg` (2048×2048). A marca fica mais ou menos em `x 535–1512`, `y 330–1328`, com centro em `(1024, 829)`. Para desenhar em outro tamanho, centralize em `(1024, 829)` e escale. Um quadro de lado `1000 / 0,86 ≈ 1163` unidades em volta desse centro já inclui o brilho da linha.

- **Cantos de enquadramento** (céu `#32B0FA`, traço 34, pontas e junções arredondadas, sem preenchimento):
  - caixa da linha central `x0=552, y0=347, x1=1495, y1=1311`;
  - cada canto tem dois braços de 159 unidades a partir do vértice e curva de raio 52 (quadrática com o vértice como controle);
  - canto superior esquerdo: `M552,506 V399 Q552,347 604,347 H711`; os outros três são simétricos.
- **Folha** (preenchimento `#FFFFFF`, contorno `#102E50` com traço 26 e junções arredondadas):
  - polígono `(850,405) (1262,490) (1375,645) (1225,1270) (660,1150)`;
  - cantos arredondados com raio 22, cortando 22 unidades de cada lado do vértice e ligando com uma quadrática que usa o vértice como controle.
- **Dobra** (preenchimento `#FFFFFF`, mesmo contorno):
  - triângulo `(1262,490) (1240,622) (1375,645)`, com cantos arredondados de raio 12.
- **Sombra da folha** (`#EEF1F8`, recortada pela folha): `M600,1145 C820,1180 1080,1110 1310,955 L1400,1400 L560,1400 Z`.
- **Linha de leitura** (`#00FD9A`):
  - `M553,851 H1495`, traço 34 e pontas arredondadas;
  - **brilho:** a mesma linha com traço 90, opacidade 0,7 e desfoque gaussiano de desvio 26, desenhada **por cima** da folha. É o que tinge o contorno da folha de verde perto da linha, como no original.
- **Ordem de desenho:** cantos, folha (preenchimento), sombra, dobra (preenchimento), contorno da folha, contorno da dobra, brilho e linha.

A geometria foi conferida sobrepondo a versão em vetor ao `logo.jpeg`: o centro de massa do contorno coincide com o do original com menos de 0,2 px de diferença a 1024 px.
