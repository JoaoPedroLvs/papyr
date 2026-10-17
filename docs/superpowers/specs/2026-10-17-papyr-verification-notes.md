# Papyr: notas da verificação técnica (2026-10-17)

Saída bruta dos 6 agentes de verificação (protótipos descartáveis no emulador API 36.1 + revisão de código-fonte + críticos da spec). Referência para o plano de implementação. A spec (2026-10-17-papyr-scanner-design.md) já incorpora as decisões; aqui ficam os detalhes e snippets testados.

## Parte 1: correções e mudanças propostas


######## AREA: Kotlin MethodChannel contract papyr/native (spec 5.2), Android platform APIs only. Native agent. Tested on emulator Medium_Phone_API_36.1 (Android 16 
--- REFUTED
* CLAIM: MethodChannel.Result must be called on the main thread, so heavy work needs a single-thread Executor plus Handler(main looper) delivery (spec 5.2 intro / task item 7).
  EVIDENCE: Emulator: result.success from an Executor thread delivered the value with no exception. Bytecode of the 3.44.5 embedding: Reply.reply -> FlutterJNI.invokePlatformMessageResponseCallback has no main-thread assertion. makeBackgroundTaskQueue() is serial by default and ran 3 concurrent calls back to back without overlap.
  FIX: Replace the Executor + Handler with one line: MethodChannel(messenger, "papyr/native", StandardMethodCodec.INSTANCE, messenger.makeBackgroundTaskQueue()) and call result.* directly in the handler. Calls stay serialized, which still covers PdfRenderer. The spec's Executor + Handler(main) design also works (verified), so this is a simplification, not a bug fix.
* CLAIM: delete throws not_owned on SecurityException, for an item the app no longer owns (spec 5.2 delete row, section 9 'Exclusão de item que o app não possui mais').
  EVIDENCE: Emulator: ContentResolver.delete throws SecurityException 'has no access to <uri>' in three cases: an own item that was already deleted, a nonexistent id (999999), and an orphaned file from an uninstalled package. It never returns 0 rows. The app cannot see non-owned rows either, so 'gone' and 'not owned' cannot be told apart. URIs only reach delete from list or save, which are always owned. So in practice SecurityException from delete means 'it vanished externally'.
  FIX: In delete, map SecurityException to not_found (the UI shows a message and refreshes the list, same as section 6.6), or treat it as success. Drop the not_owned code from the error list and from the section 9 table. Note: read/thumbnail/pdf* of an own deleted item already throw FileNotFoundException, which maps to not_found.
* CLAIM: PdfRenderer might be strict about xref, so xref correctness is critical (task item 5).
  EVIDENCE: Emulator: wrong xref offsets (+7) and a missing xref table with a bogus startxref both open and render correctly through PdfRenderer (pdfium rebuilds the xref). Only a truncated file fails ('Unable to load the document!').
  FIX: Keep the xref/startxref unit tests in pdf_writer_test.dart for external viewers, but xref bugs will NOT show up in the in-app viewer. Do not rely on PdfRenderer as a validator.
--- SPEC CHANGES
* [important] 5.2 delete / 9 Tratamento de erros: delete: catch SecurityException and report not_found (or success) instead of not_owned. Remove not_owned from the error codes: it is unreachable for listed items and misleading for the real case, an item deleted from outside the app.
* [important] 5.2 warp: State explicitly: android.media.ExifInterface has no getRotationDegrees(), so use an explicit 8-case orientation table (snippet in implementationNotes). Map corners with the inverse of the raw->upright matrix, measure edges in raw pixels (isometric, same as upright), and fold the rotation param into the same Matrix (postConcat a setRotate matrix translated by -mapRect bounds) so only 2 bitmaps exist. Recycle src right after drawBitmap and recycle both in finally.
* [minor] 5.2 intro (threading): Use MethodChannel(messenger, "papyr/native", StandardMethodCodec.INSTANCE, messenger.makeBackgroundTaskQueue()) (serial by default) and call result.* directly. No Executor or Handler needed. share/openAppSettings startActivity from that thread works (tested).
* [minor] 5.2 list: One MediaStore.Files query: selection relative_path IN ('Pictures/Papyr/','Documents/Papyr/'), sort 'date_added DESC, _id DESC'. Rebuild image URIs with ContentUris.withAppendedId(MediaStore.Images.Media.getContentUri(VOLUME_EXTERNAL_PRIMARY), id) and PDFs with the Files URI. Use VOLUME_EXTERNAL_PRIMARY for both insert and list, so the uri strings from save and list are identical (thumbnail cache key). date = DATE_ADDED*1000.
* [minor] 5.2 preview: Optional simplification, tested: ImageDecoder.decodeBitmap(createSource(File(path))) { d, info, _ -> ... } reports info.size already upright, applies EXIF itself and setTargetSize gives the exact maxSide; set allocator = ALLOCATOR_SOFTWARE. It removes the inSampleSize loop and matrix. Map ImageDecoder.DecodeException to 'decode'. The BitmapFactory + inSampleSize + EXIF matrix version in the spec also works (tested).
* [minor] 5.2 thumbnail / 6.6: loadThumbnail(Size(s,s)) can return more than s on one axis (211x296 for s=256), so Dart must display it with BoxFit (cover or contain) and not assume s x s.
* [minor] 8 PDF / 10 Testes: Note that PdfRenderer is tolerant of bad xref offsets, so the xref unit tests are the only guard for strict external viewers. A truncated file fails with IOException (io).
* [minor] 11 Riscos (memória): Make the number precise: warp peak = (srcW*srcH + outW*outH)*4 bytes. Measured +70 MB for a 12MP sheet crop and +92 MB for full-frame. Bitmap pixels are in the native heap (API 26+), so failure is a native allocation failure or OutOfMemoryError; keep catching Throwable and mapping OOM to 'memory'. The emulator timings (about 0.35 s per 12MP page) come from a desktop CPU; expect several times slower on an entry-level phone.
* [minor] 5.2 save: Confirmed as written: duplicate names come back renamed ('x (1).jpg') and the pending row is removed on failure. A missing temp file surfaces as not_found (FileNotFoundException). Use buffered copy (copyTo with a 64 KB buffer).
* [minor] 5.2 share: Confirmed as written (SEND, SEND_MULTIPLE, mixed */* all readable by another app). FYI, not tested: Intent.migrateExtraStreamToClipData would add ClipData and FLAG_GRANT_READ_URI_PERMISSION automatically for SEND/SEND_MULTIPLE. Keep them explicit; they are harmless.


######## AREA: Section 7: the pure-Dart quad detector, and section 6.3 step 4: whether the live pipeline is feasible. All runs were on the desktop: Dart 3.12.2, AOT 
--- REFUTED
* CLAIM: Section 7 step 2: high = 90th percentile of the magnitude and low = 0.4 x high are suitable adaptive thresholds.
  EVIDENCE: Held-out synthetic results: low contrast 13/40 and white on white 1/40 with the spec thresholds; 0/40 for both with the percentile over NMS pixels. Edge maps show the text strokes push p90 up to 37-218 while the page border (Sobel peak about 2.5 x contrast, so 40-75) disappears. On blank or textured frames p90 sits inside the noise and gives 20-33% edge pixels.
  FIX: high = max(25, 4 x median(|grad|)) and low = 0.3 x high. The median tracks noise and texture; the floor of 25 is about a 10 gray-level step after the 5x5 blur. Measured with this: low contrast 40/40 and white on white 37/40 (40/40 with 2x2-averaged input). No percentile is needed.
* CLAIM: Section 7 steps 5-6: taking the largest convex candidate with area >= 20% is enough, and the section 10 test 'imagem sem folha deve dar null' would pass.
  EVIDENCE: No-document frames (noise, wood texture, small rectangles, smooth gradient): 40/40 false positives, usually the full frame. Clutter: 29/40 wrong quads, because the page border merges with the table edge or the pen and the hull grows past the page.
  FIX: Add a per-side contrast support check (details in the spec changes) and reject candidates with more than 2 sides on the frame border; score = area x mean support. Measured: no document 40/40 null; clutter has 2/40 wrong, the rest found or missed.
* CLAIM: Section 7 step 6: TL = min(x+y), BR = max(x+y), TR = min(y-x), BL = max(y-x) gives a valid corner order.
  EVIDENCE: check.dart: the quad (160,20),(260,110),(150,230),(60,120) gives BR == BL. Rotated 35-53 deg with perspective: 14/40 results had duplicate corners, so the warp and editor would get a degenerate quad.
  FIX: Keep the hull's cyclic order (positive shoelace area = TL->TR->BR->BL in image coordinates) and rotate it so index 0 is the vertex with min(x+y). This can never repeat a corner.
* CLAIM: Section 7 step 5: the convexity check filters candidates.
  EVIDENCE: A 4-point DP result is a subset of the convex hull's vertices in cyclic order, so it is always convex. The check never rejected anything in any run.
  FIX: Drop it from the detector and keep isConvex only for validating editor drags (section 6.4).
--- SPEC CHANGES
* [blocker] 7.2 (Canny thresholds): Replace 'alto = percentil 90, baixo = 0,4 x alto' with 'alto = max(kMinHigh=25, kNoiseK=4 x mediana da magnitude Sobel), baixo = 0,3 x alto'. Use strict > in hysteresis so lo = 0 can never flood the image.
* [blocker] 7.5/7.6 (candidate validation and choice): Add a per-side contrast support check on the blurred image: sample 3 px inside and 3 px outside the side over its middle 80%. A sample counts if |in-out| >= 8 and has the side's dominant sign. Every side not lying on the frame border needs >= 0.6. A side whose two endpoints are within max(3 px, 1.5% of the larger dimension) of the same border is skipped; more than 2 such sides means reject. Pick the best area x mean support instead of the largest area.
* [blocker] 7.6 (corner ordering): Replace the sum/diff rule with cyclic hull order rotated so TL = min(x+y). Add to section 10 a test asserting 4 distinct corners for a perspective quad rotated about 45 deg.
* [important] 7.4 (candidates): Besides the 8-connected edge components, also label 4-connected components of NON-edge pixels (the page interior) and run the same hull / DP / validation on them, pushing each side out 2 px (the interior hull sits about 2 px inside the edge). Measured: clutter 0 -> 25/40. Cost: +1.5 ms on the desktop.
* [important] 7.5 (page partly outside the frame): When DP produces 5 points and two adjacent ones lie on the same frame border, replace them with the intersection of the two neighbouring sides, as long as it is beyond that border and less than 30% outside. Score it alongside the 4-point result, then clamp the output to 0..1. Measured: partial 22 -> 31/40 with 0 wrong.
* [important] 6.3.4 (Y plane copy): Do not copy the whole plane. Subsample straight from plane.bytes with precomputed x/y index tables and a 2x2 average at each sample point (179 us vs 740 us for copy-then-subsample on the desktop; it also helps white on white: 37 -> 40/40). Compute the step from each frame's width and height, because CameraX may give a stream other than 1440x1080 with ResolutionPreset.max. Never assume bytes.length == bytesPerRow x height: the last row has no padding, so length ~/ bytesPerRow = height - 1.
* [minor] 6.3.4 (isolate message): Send the 320x240 Uint8List with a plain SendPort.send (3 us). Do not use TransferableTypedData for this size (31 us). TransferableTypedData only pays off for MB-sized buffers.
* [important] 6.3.4 (rotation + EMA): After rotating the corners by sensorOrientation into portrait, run the cyclic ordering again (a 90 deg rotation moves the TL label). Before the EMA (alpha 0.5), shift the new corners cyclically to the rotation with the smallest total distance to the previous corners. Otherwise a TL flip near 45 deg (22/40 label flips measured) makes the averaged outline collapse.
* [minor] 6.3.4 / 11 (stream cost): Record that camera_android_camerax 0.7.5+1 copies all 3 planes (~3 MB at 1440x1080) to the Dart main isolate on every frame, even while the detector is busy. Also record that the 'pull' model is cheap there (cancel = clearAnalyzer, listen = setAnalyzer, no rebind). Measure main-thread jank on a low-end phone and switch to pull if needed.
* [minor] 7 (constants block): Recommended constants: blur [1,4,6,4,1]; kMinHigh 25; kNoiseK 4; kLowRatio 0.3; one 3x3 dilation; kMinBBoxFrac 0.20; kMinAreaFrac 0.20; DP eps 0.01..0.05 step 0.005; kSupportOffset 3 px; kSupportTrim 0.10; kMinDiff 8 (5-8 equivalent); kMinSideSupport 0.6 (0.5-0.7 equivalent); kBorderTol max(3 px, 1.5%); kMaxBorderSides 2; kRegionGrow 2 px; kCutCornerMaxOut 0.30. Normalize with (x+0.5)/w.
* [minor] 10 (detector tests): Also cover no document on noise and on texture (the spec's own algorithm fails this), a low-contrast page, a white page on a light desk with gradient light, clutter touching the page, a cut corner, and distinct corners at 45 deg. The 3% tolerance is fine: median errors were 0.4-0.6%.


######## AREA: Minimal PDF writer (spec section 8, pdf_writer.dart + pdf_writer_test.dart). Final prototype: /tmp/claude-1000/-var-www-projetos-pessoal-scanner/d545c
--- REFUTED
* CLAIM: Section 8: 'Recebe a lista de (caminho, largura, altura) que o warp devolve, para nao precisar ler o JPEG de novo' (taking width/height from the caller is safe and saves a read).
  EVIDENCE: Ran: a /Width//Height that disagrees with the JPEG SOF (for example w and h swapped by a rotation bug in warp) renders garbage silently in poppler and gs. The writer reads the whole JPEG anyway to copy it, so reading the first 64 KB to parse SOF costs nothing measurable.
  FIX: writePdf(String outPath, List<String> jpegPaths). Parse /Width, /Height and the component count from the first SOFn marker of each JPEG (jpegInfo, about 15 lines). warp can keep returning width/height for UI use.
* CLAIM: Section 8: 'Escrita em stream num IOSink (ja tem buffer)', implying plain IOSink usage with try/catch is enough.
  EVIDENCE: Ran: a missing output directory and ENOSPC produce an unhandled async error from IOSink.done that bypasses try/catch (process crash in the CLI). Source read: IOSink does not coalesce writes; each add() is one writeFrom.
  FIX: Call sink.done.ignore() immediately after openWrite(). Errors then surface from the next addStream() or close() (both return done). In catch: await sink.close().catchError((_) {}); await file.delete().catchError((_) => file); rethrow. Delete is best effort so it never masks the original error.
* CLAIM: Section 8: the image is always '/ColorSpace /DeviceRGB'.
  EVIDENCE: True for ARGB_8888 Bitmap.compress output (inferred from Android behaviour, not run on a device). But a 1-component or 4-component JPEG declared DeviceRGB renders garbage silently (ran in poppler and gs).
  FIX: Derive the colour space from the SOF component count: 1 -> /DeviceGray, 3 -> /DeviceRGB, anything else -> throw FormatException. CMYK would need /DeviceCMYK plus /Decode [1 0 1 0 1 0 1 0] for Adobe-inverted JPEGs: YAGNI, reject it.
--- SPEC CHANGES
* [important] 8. Gerador de PDF: Change the input to a list of JPEG paths only, and read width/height/components from the JPEG SOF marker (first 64 KB of the file) instead of trusting the (caminho, largura, altura) from warp. Reason: a mismatch renders silently garbled pages in poppler and gs (verified).
* [important] 8. Gerador de PDF: Add IOSink error handling: `sink.done.ignore()` right after `File(out).openWrite()`. On any error, close the sink, delete the partial file best-effort, and rethrow. Without it, ENOSPC or an open failure become an unhandled async error instead of a catchable exception (verified on desktop). Also drop the claim that IOSink 'ja tem buffer': it queues but does not merge writes.
* [minor] 8. Gerador de PDF: ColorSpace from SOF component count: 1 -> /DeviceGray, 3 -> /DeviceRGB, otherwise FormatException (no CMYK).
* [minor] 8. Gerador de PDF: Write down the object numbering and byte rules (see implementationNotes): 1 Catalog, 2 Pages, page i -> 3+3i Page, 4+3i Contents, 5+3i Image; xref entries exactly 20 bytes; heights via toStringAsFixed(2); header with a binary comment line.
* [minor] 8. Gerador de PDF / 6.5 Salvar: State explicitly that only warp output (upright pixels, no EXIF) is fed to the writer. PDF renderers ignore EXIF Orientation inside DCTDecode (verified in poppler and gs).
* [important] 10. Testes (pdf_writer_test.dart): Beyond the 4 listed checks, add: every xref entry is exactly 20 bytes and entry 0 equals '0000000000 65535 f ' + LF; trailer /Size; /Length matches for EVERY stream (content and image); MediaBox height for a non-square page; DeviceGray for a 1-component JPEG; and error cases that must throw and leave no file behind: CMYK input, a missing input JPEG, an unwritable output path. Use test(), not testWidgets(): real file I/O does not complete inside FakeAsync. Lenient viewers repair broken xref silently, so this test is the only strict guard.


######## AREA: Camera screen correctness (spec 6.3): camera 0.12.1 + camera_android_camerax 0.7.5+1 + camera_platform_interface 2.15.0, read from ~/.pub-cache/hosted
--- REFUTED
* CLAIM: 5.3: RECORD_AUDIO, READ_EXTERNAL_STORAGE and WRITE_EXTERNAL_STORAGE must be removed because the plugin injects them.
  EVIDENCE: The plugin manifest injects only CAMERA, RECORD_AUDIO and WRITE_EXTERNAL_STORAGE (maxSdkVersion=28). READ_EXTERNAL_STORAGE is not declared, and the CameraX AARs declare no permissions.
  FIX: Remove only RECORD_AUDIO and WRITE_EXTERNAL_STORAGE. The READ_EXTERNAL_STORAGE remove line is dead (harmless), so drop it.
* CLAIM: 6.3.5: the flash/torch state is reapplied every time the controller is recreated (implying setFlashMode(torch) is enough).
  EVIDENCE: torchEnabled lives on the singleton AndroidCameraCameraX and is never reset on dispose or create. A new controller's setFlashMode(torch) returns early, so the torch stays off while the UI shows it on.
  FIX: Make it mandatory: after every initialize(), call setFlashMode(FlashMode.off) FIRST, then setFlashMode(FlashMode.torch) if the user's toggle is on. Step 2 already calls off, but the spec must say this order is required.
* CLAIM: 6.3.8: the controller is disposed on inactive (unconditionally).
  EVIDENCE: initialize() shows the system permission dialog from inside createCameraWithSettings, and the dialog moves the app to inactive. Disposing then waits for the pending initialize, opens and immediately closes the camera, and overlaps with the recreate on resumed (singleton dispose race).
  FIX: On inactive, dispose only if controller.value.isInitialized. On resumed, create only if there is no controller and none is being created.
* CLAIM: 6.3.8: if the last attempt failed with CameraAccessDenied, the app retries on resumed.
  EVIDENCE: When the permission is permanently denied, requestPermissions returns a denial without UI but still starts and finishes the system permission activity, which causes a pause/resume. Auto-retry on resumed can then loop. This is inferred, not run on a device.
  FIX: Retry on resumed only if the user tapped 'Abrir ajustes' (a flag). Otherwise wait for 'Tentar novamente'.
* CLAIM: 11: setJpegImageQuality(100) recreates the capture and only the first photo of the SESSION can be slower; 'if the analysis stream grows a lot' the call can be removed.
  EVIDENCE: The call only builds an unbound ImageCapture. The bind and session reconfiguration happen inside the next takePicture, and the call must be repeated for every new controller. So the slow first shot (plus a preview/analysis hiccup) recurs after every tab switch, resume or return from the editor. It has nothing to do with the analysis stream.
  FIX: Reword. Recommendation: drop the call. The CAP file is intermediate, warp re-encodes at 100, and CameraX's default of 95 saves one reconfiguration per controller.
* CLAIM: 6.3.4: copy the Y plane respecting bytesPerRow with rows = min(height, length ~/ bytesPerRow).
  EVIDENCE: The last row of the Y buffer can be unpadded, so length ~/ bytesPerRow == height-1: the formula silently drops a row. Copying the full plane (about 1.5 MB at 1440x1080) is unnecessary.
  FIX: Validate once with length >= (h-1)*bytesPerRow + w, then sample the ≤320 px image directly from plane bytes, rotated upright during sampling (snippet in implementationNotes). No full copy, and no corner rotation afterwards.
* CLAIM: 6.1/6.3.8: the camera is released when leaving the tab or on inactive (implicitly, the only cases where it runs in the background).
  EVIDENCE: The crop editor and save screen are pushed on the root Navigator over the Scaffold. The Escanear tab stays mounted (maintainState), so preview, analysis stream and TORCH keep running behind the editor, and a resumed event there would even recreate the camera.
  FIX: Stop the camera before pushing the editor and restart it when the push future completes. In resumed, skip the restart when ModalRoute.of(context)?.isCurrent == false.
--- SPEC CHANGES
* [important] 6.1 / 5.1 session.dart (tab switch): Keep the session outside the tab widget: one top-level `final session = Session();` (ChangeNotifier) in scan/session.dart. The camera is still disposed on tab switch (no IndexedStack), but photos, corners and rotation survive. No prompt on tab switch. Because nothing is lost on back either, drop the PopScope or confirm dialog from the camera, editor and save screen: back from Escanear only switches to Arquivos, and back from the editor returns to the camera with the session intact. The session ends with Concluir after saving (session.clear() + cleanCache). Open question for the user: whether a 'Descartar sessão' action is needed beyond removing photos one by one.
* [important] 6.3.6-7 / 6.1 (routes over the camera): Before pushing the crop editor, stop the camera: remove CameraPreview from the tree, then dispose, which also turns off the torch and the stream. Restart after `await Navigator.push` completes. In didChangeAppLifecycleState(resumed), do not restart while another route covers the tab.
* [important] 6.3.8 lifecycle: (1) On inactive, dispose only if value.isInitialized (permission dialog case). (2) Serialize: keep a top-level `Future<void> _lastDispose` and `await` it before creating a new controller, because platform dispose acts on singleton fields and can unbind the new camera. (3) Remove CameraPreview from the tree (setState _c=null) before calling dispose, since buildPreview throws on a disposed controller. (4) Auto-retry on resumed only after 'Abrir ajustes'. (5) Ignore 'CameraPermissionsRequestOngoing'. (6) onFrame must drop frames whose controller is not the current one, because frames can arrive after dispose.
* [important] 6.3.2 / 6.3.5 flash: Make the order mandatory after every initialize(): setFlashMode(off), then setFlashMode(torch) if the toggle is on, because the plugin keeps a stale torchEnabled across controllers. Also note that a device with no flash unit fails silently (no API to detect it).
* [minor] 6.3.4 detection input: Replace 'copy the Y plane then downsample, then rotate the corners by sensorOrientation' with: sample the Y plane straight into an UPRIGHT ≤320 px gray image (rotation applied while sampling, bounds check (h-1)*bytesPerRow+w <= length). The detector then always sees upright images (same as in the editor), returns TL,TR,BR,BL in screen space, and those 8 doubles multiply directly by the CustomPaint size. The EMA stays per corner index.
* [minor] 6.3.3 preview layout: Put CameraPreview under Center (e.g. ColoredBox(black) > Center > CameraPreview(c, child: CustomPaint(...))). AspectRatio needs loose constraints. Under tight constraints it stretches, and the overlay would still match the box but the image would be distorted. Do not hardcode 3:4; CameraPreview derives it from previewSize.
* [minor] 5.3 Manifest: Remove only RECORD_AUDIO and WRITE_EXTERNAL_STORAGE (READ_EXTERNAL_STORAGE is not injected). Keep the plugin's uses-feature android.hardware.camera.any.
* [minor] 11 risks / 6.3.2: setJpegImageQuality cost recurs per controller, paid at the first takePicture after each (re)creation. Recommend removing the call (output is re-encoded at 100 by warp). If it is kept, call it right after lockCaptureOrientation; its position relative to startImageStream does not matter.
* [minor] 10 manual checklist: Add: (1) log img.width/img.height of the first frame vs controller.value.previewSize once; the overlay assumes equal aspect ratios (same full-FOV crop). (2) Analysis resolution and fps with ResolutionPreset.max, since the same selector is shared with capture and all 3 planes cross the channel each frame. (3) Torch stays lit through takePicture, including the first shot after the ImageCapture rebind. (4) Tab switch and editor round trip with the torch on.
* [minor] 4 / 6.3 orientation: State the ceiling: the mapping assumes display rotation 0 (a phone in portrait). A natural-landscape tablet locked to portrait would need (sensorOrientation - displayRotation), and the camera plugin does not expose display rotation to Dart.


######## AREA: Spec critique: user flows and requirements coverage (Papyr design spec 2026-10-17). No code written, nothing touched under /var/www/projetos/pessoal/s
--- REFUTED
* CLAIM: 5.3: RECORD_AUDIO, READ_EXTERNAL_STORAGE and WRITE_EXTERNAL_STORAGE are removed 'porque o plugin as injeta' (because the plugin injects them).
  EVIDENCE: The camera_android_camerax-0.7.5+1 manifest injects only CAMERA, RECORD_AUDIO and WRITE_EXTERNAL_STORAGE (maxSdkVersion=28). It never injects READ_EXTERNAL_STORAGE.
  FIX: Say the plugin injects RECORD_AUDIO and WRITE_EXTERNAL_STORAGE (maxSdk 28). Removing all three with tools:node=remove is harmless; the checklist should check the merged release manifest.
* CLAIM: 6.1 (implied): the camera's PopScope (when the session has photos) works on its own, separate from the root rule 'back on Escanear/Ajustes goes to Arquivos'.
  EVIDENCE: routes.dart:2045-2048: every PopScope inside the root route gets onPopInvoked. The root handler would switch to the Arquivos tab, which disposes the camera and the session, while the camera handler opens its confirmation dialog. Both run.
  FIX: Use ONE back handler at the root Scaffold that decides from (tab index, session empty?).
* CLAIM: 6.1: the body is [tabs][index] without IndexedStack 'so the camera is disposed when the tab changes'. Together with 6.3.8, this implies the camera is only active while visible.
  EVIDENCE: MaterialPageRoute has maintainState=true (page.dart:41). With the editor, save screen or viewer pushed on the root Navigator, the Escanear tab stays mounted: controller, image stream, detector isolate and torch keep running during editing and warp. Because lifecycle 'resumed' recreates the controller and turns the torch back on, coming back from the Share sheet on the save screen would reopen the camera and torch where nobody can see them.
  FIX: Release the camera when a route covers it (RouteAware didPushNext/didPopNext, or check ModalRoute.isCurrent). Recreate it only when the Escanear tab is selected and its route is on top.
* CLAIM: 6.3.8: dispose the controller on 'inactive' and recreate it on 'resumed' is safe.
  EVIDENCE: (a) The permission dialog appears during initialize(), which causes inactive then resumed, so the spec disposes the controller in the middle of initialize(). dispose() waits for that initialize to finish and then calls the plugin's dispose. (b) The plugin's dispose ignores cameraId and runs unbindAll() and releaseSurfaceProvider() on whichever Preview is current, which may already belong to the controller created on resumed. On the very first launch, granting the permission can therefore leave a black preview and no frames. This is an inferred race from reading the source; not tested on a device.
  FIX: Never start creating a new controller until the previous dispose() future has completed (one global Future chain). Dispose on paused/hidden instead of inactive (the permission dialog and the notification shade only cause inactive), and ignore lifecycle events while initialize() is still running.
* CLAIM: 6.3.8 and 9: 'if the last attempt failed with CameraAccessDenied, try again on resumed' gives the intended retry-after-Settings behaviour.
  EVIDENCE: Denying the dialog returns to resumed. The rule retries right away, and Android shows the dialog again until the second denial. The user is forced to deny twice in a row. Inferred from Android permission rules; not tested on a device.
  FIX: Retry on resumed only if the user tapped 'Abrir ajustes' (set a flag there), or when they tap 'Tentar novamente'.
* CLAIM: 4 and 5.3: 'App travado em retrato' (app locked to portrait) through android:screenOrientation=portrait.
  EVIDENCE: The Flutter template targets SDK 36. Android 16 ignores orientation, resizability and aspect-ratio limits on displays with smallest width of 600dp or more (tablets, unfolded foldables) for apps targeting 36. This comes from the Android 16 behaviour-changes documentation, not from a device test.
  FIX: Either declare phones-only and accept that tablet layout and camera mapping rotate (put this in section 11), or make the coordinate mapping work in any orientation. Do not claim the app is locked everywhere.
* CLAIM: 2.12 and 4: the only external dependency is camera.
  EVIDENCE: The `flutter create` command in section 12 adds cupertino_icons: ^1.0.8 (plus the dev dependency flutter_lints: ^6.0.0) to pubspec.yaml. The spec also adds camera_android_camerax as a second direct dependency.
  FIX: Add a step: delete cupertino_icons after create. Decide on flutter_lints (dev only). Note that keeping camera_android_camerax as a direct dependency is a deviation the user must accept; otherwise rely on the versioned pubspec.lock.
* CLAIM: 6.3.2: setJpegImageQuality(100) is called 'uma única vez' (only once).
  EVIDENCE: 6.3.8 recreates the controller 'with all the configuration again (orientation, quality, flash, stream)'. Section 11 says the call may be removed. Each recreate unbinds and rebinds ImageCapture again (source read), so every return to the tab makes the next first photo slow again.
  FIX: Make a final decision: either once per controller, or drop the call entirely (CameraX default is 95 and warp re-encodes at 100). Remove the conditional wording.
--- SPEC CHANGES
* [blocker] 5.1 / 6.1 / 6.3: who owns the session: The spec never says where scan/session.dart lives. If it lives in the camera screen's State, switching tabs (no IndexedStack, PopScope does not cover tab taps) silently loses every photo and orphans the CAP files. If it lives at the root, it survives. The plan cannot choose. Simplest fix: one session object at the root, next to library. It survives tab switches; when Escanear is rebuilt it shows the existing thumbnail strip. No dialog on tab tap.
* [blocker] 6.1 / 9: back stack: As written, back from the editor and from the save screen 'asks to confirm discarding the session'. That rules out going back to take a forgotten page and throws away all the work from the save screen. Define it like this: Camera with photos, back: confirm, discard, go to Arquivos. Editor, back: return to the camera with the session kept (more photos can be added; the next 'Concluir (n)' keeps the existing corners). Save screen idle, back: return to the editor. Save screen while processing: back is ignored. Save screen after success, back: same as Concluir. Use a single root back handler (see refuted).
* [blocker] 6.5.4: state after a successful save: cleanCache deletes the CAP files while the session still points to them, and the PopScope is off once the save finishes. A normal back then pops to the editor, whose files are gone, and lets the user save the same session again. Required: on success, clear the session and run cleanCache right away; system back acts like Concluir (pop to the first route, tab = Arquivos, library.refresh()). Also state that opening Escanear afterwards shows a fresh, empty camera.
* [blocker] 6.3.8: camera lifecycle: Serialize controller creation after the previous dispose has finished. Dispose on paused/hidden instead of inactive. Also release the camera when a route is pushed over it and recreate it when that route pops. Torch state is reapplied only when the camera is actually visible. Add 'first launch: grant permission, preview appears' and 'switch tabs fast several times' to the checklist.
* [important] 6.3.8 / 9: permission retry: Retry on resumed only after 'Abrir ajustes' (use a flag); otherwise retry only on 'Tentar novamente'. A camera start failure that is not about permission (camera busy, blocked by policy) currently gets only a snackbar over a black tab. Show the same message screen with 'Tentar novamente' and without 'Abrir ajustes'.
* [important] 6.5.5: retry after a partial save in Imagens mode: 'Tentar de novo' would save every photo again and create duplicates like 'X_01 (1).jpg'. Store the saved URI per photo in the session, resume from the first unsaved photo, lock the Imagens|PDF selector after a partial save, and have Compartilhar include every saved URI.
* [important] 6.5.1: name rules: Spell out the rules. Remove `\ / : * ? " < > |` and control characters, trim spaces, strip leading dots (otherwise the file is hidden), fall back to the default name when the result is empty, and set a maximum length (about 100 characters; the filesystem limit is 255 UTF-8 bytes, and accented letters take 2 bytes, before adding '_NN.jpg' and MediaStore's ' (n)'). The temporary files must not use the user's name: use a fixed papyr_out.pdf, and give warp outputs a papyr_ prefix (unspecified today) so cleanCache removes them.
* [important] 6.4: editor edge cases: Not covered today. Removing the last photo returns to the camera with an empty session. 'Concluir (n)' is disabled when n = 0. A page whose preview fails to decode shows an error tile with 'Remover'. Detection runs once per photo, and its result is stored in the session separately from the user's corners (PageView throws away pages that scroll off-screen, so re-running detection on rebuild would overwrite manual edits; 'Redefinir' also needs the detected corners kept). Corners are clamped to 0..1, and the image is padded so the 48dp handles can still be grabbed when the default is the full image. Decide whether 'Girar 90°' rotates the image and handles on screen or only shows an indicator.
* [important] 6.5.3 / 8: disk usage during save: PDF mode keeps every warped JPEG, plus the temporary PDF, plus the MediaStore copy at the same time, roughly 3× the final size (more than 600 MB for 20 pages). Delete each warped file as soon as it has been used. That means the PDF writer must accept pages one at a time (begin, addPage, finish) instead of 'receiving the list'. In Imagens mode, delete each temp file right after it is saved.
* [important] 6.5: cancel or back while processing: Not specified. Simplest: no cancel button; back is ignored while 'Processando'. Also show progress for the PDF writing and copy stage ('Gravando PDF...'), which can take seconds for 200 MB.
* [important] 6.6: PDF viewer: 'ListView.builder inside InteractiveViewer' can be built two ways, and the pan and scroll gestures conflict. Page sizes are also unknown because pdfInfo returns only pageCount, so the layout jumps while pages load. Make pdfInfo return each page's aspect ratio (or the first page's), and pick one zoom model (for example zoom per page, or one InteractiveViewer with constrained:false).
* [important] 2.12 / 12: dependencies and language: Remove cupertino_icons after `flutter create`. Decide on flutter_lints. Decide whether Material's built-in strings (copy/paste toolbar on the name field, tooltips) can stay in English or whether flutter_localizations is allowed (it pulls in intl and path). With no intl, dates (dd/MM/aaaa HH:mm) and sizes ('12,3 MB', comma decimal) are formatted by hand.
* [important] 4 / 11: orientation on large screens (Android 16): State that the portrait lock does not apply on tablets and foldables with targetSdk 36. Either scope the app to phones and say so, or handle the rotation.
* [important] 6.2: edge-to-edge: targetSdk 36 forces edge-to-edge. The custom SnakeBar has to add the system bottom inset itself (gesture bar or 3-button bar), and the camera's black area sits under the status bar. Not mentioned today.
* [minor] 6.3.4 / 11: TBDs written as conditionals: 'If it stutters, use the pull model' and 'if the stream grows a lot, the call is removed' are open decisions a plan cannot implement. Decide now; for example, start with the busy-flag model and keep the pull model as a documented upgrade path, not part of this plan.
* [minor] 6.4 vs 7: detector input size: In the editor, 'targetWidth up to 320' on an upright portrait image gives about 320×427, which breaks the detector rule of at most 320 px on the longer side. Use targetHeight when the image is taller than wide.
* [minor] 6.6: viewer and list consistency: Define what happens after deleting from a viewer: confirm, close the viewer, refresh the list, show a snackbar. Define what happens when a file is deleted elsewhere while the PDF viewer is open (pdfPage fails with not_found): show a message and close. State that the list refreshes after a delete as well as on pull-down and resume.
* [minor] 6.x: loading and empty states: Only the empty list and 'Processando' are specified. Add the camera starting, editor preview loading, first list load and list error, thumbnail and PDF page placeholders, and a list that is long but slow to get thumbnails (the single native thread can queue dozens of thumbnail requests ahead of opening a viewer; only request thumbnails for rows still on screen).
* [minor] 6.3.6 / 6.3.7: taps during capture: Disable the shutter while controller.value.isTakingPicture; otherwise a double tap throws 'Previous capture has not returned yet' and shows the misleading 'Falha ao capturar'. Show a visual capture cue. Block repeated taps on Concluir and Continuar so the same route is not pushed twice.
* [minor] 6.3.5: flash: Write down that 'botão de flash' means torch only (no auto, no flash at capture), and how long the torch state lasts (per session or per app).
* [minor] 6.1 / 5.1: wording: State the starting tab (implied to be Arquivos). Line up the class names ArquivosTab, EscanearTab and AjustesTab with the file names files_screen, camera_screen and settings_screen. Hide the '1 de 1' counter when there is only one photo.
* [minor] 9: things that can never recover: If warp fails with a memory error, retrying fails the same way, and requirement 6 forbids downscaling. Say so in the message (suggest removing that photo). App killed mid-session: say the session lives only in memory and is lost, its CAP files are cleaned at the next start, and a save killed halfway can leave an IS_PENDING row that the default MediaStore query hides and that expires (inferred, not tested).
* [minor] 10: manual checklist: Add: merged release manifest has no INTERNET and no RECORD_AUDIO; switch tabs during a session; first-launch grant shows the preview; deny once (asked only once); Compartilhar, then back, after a save; retry after a partial save; long or accented names. Replace 'performance on an entry-level phone' with numbers (for example outline updates of 5/s or more, warp of 3 s or less per page).
* [minor] Scope: Right-sized for ONE plan, as long as tasks are ordered as vertical slices so manual cropping works without the detector. 1) create, manifest, native channel save/list/delete/share/thumbnail, Files tab with SnakeBar. 2) Camera capture (no detection), editor with manual corners, warp, save as Imagens. 3) PDF writer and PDF mode. 4) Viewers. 5) Detector with tests, then the live outline. 6) Settings and the checklist. Remove the 'pull model' contingency and the conditional setJpegImageQuality removal from this plan. If it must shrink: the in-memory thumbnail cache and the space-used figures in Ajustes are the cheapest cuts. No split into separate specs needed.


######## AREA: Spec critique: technical consistency and Android/Flutter correctness (Papyr design spec 2026-10-17). Note: the earlier probe dirs (probe, cvbench, pdf
--- REFUTED
* CLAIM: 5.3: the plugin injects READ_EXTERNAL_STORAGE, so it must be removed
  EVIDENCE: camerax 0.7.5+1 AndroidManifest.xml declares only CAMERA, RECORD_AUDIO and WRITE_EXTERNAL_STORAGE (maxSdkVersion 28)
  FIX: Remove only RECORD_AUDIO and WRITE_EXTERNAL_STORAGE. The READ removal is a harmless no-op but the text is inaccurate. Add xmlns:tools to <manifest>.
* CLAIM: 6.3.2 setJpegImageQuality(100) is called 'uma única vez' while 6.3.8 re-applies 'qualidade' on every controller re-creation; section 11 treats it as optional
  EVIDENCE: setJpegImageQuality unbinds ImageCapture and creates an unbound one, causing two session reconfigurations each time (source). The controller is re-created on every resume. Inferred, not device-tested: between that call and the first takePicture only Preview+ImageAnalysis are bound, and CameraX may then pick YUV at MAXIMUM (full-sensor frames copied to Dart every frame).
  FIX: Drop setJpegImageQuality. The CameraX default is 95 and the warp re-encodes at 100 anyway. This removes the 'primeira foto mais lenta' risk too.
* CLAIM: 7.6 ordering TL=min(x+y), BR=max(x+y), TR=min(y-x), BL=max(y-x) yields 4 corners
  EVIDENCE: dart run: a 45-degree diamond produced 3 distinct corners. Near 45 degrees the label assignment flips between frames, so EMA per index averages different physical corners and the outline twists.
  FIX: Take the 4 hull/DP points in their cyclic (convex) order and rotate the list so the point with min(x+y) is first, then go clockwise in image coordinates. Re-sort after the sensorOrientation rotation in the live path. Add a 45-degree case to detector_test.
* CLAIM: 6.4: targetWidth up to 320 gives the same detector input as live (section 7: max 320 on the longer side)
  EVIDENCE: Upright previews are portrait 3:4, so targetWidth=320 gives 320x427.
  FIX: Pass targetHeight=320 when h>w and targetWidth=320 otherwise (only one of the two, to keep aspect).
* CLAIM: 6.1: PopScope on the camera plus 'Voltar na aba Escanear leva para Arquivos' work independently
  EVIDENCE: Both live on the same root route. Flutter calls every PopEntry's onPopInvokedWithResult, so a back press both switches the tab (disposing the camera and the session) and opens the discard dialog.
  FIX: Use a single PopScope at the root with canPop: index==0 && !session.hasPhotos. Its callback shows the confirmation if Escanear has photos, otherwise sets index=0. Keep separate PopScopes only on pushed routes (editor, save).
* CLAIM: 6.3.8: disposing the controller on `inactive` and re-creating it on `resumed` is safe
  EVIDENCE: Source: the first initialize() requests permission, the system dialog fires `inactive`, dispose() then awaits the pending initialize. On `resumed` a second controller starts on the same global AndroidCameraCameraX state. The old controller's later dispose() calls unbindAll() and can kill the new controller's use cases. Quick tab switches (State.dispose cannot await) overlap the same way. Inferred from source, not device-tested.
  FIX: Dispose on hidden/paused, not inactive. Serialize the camera lifecycle through one static Future chain (await the old dispose before creating the new controller). After every await, check mounted and that the controller is still current.
--- SPEC CHANGES
* [blocker] 5.3 Manifest: Say explicitly to add xmlns:tools="http://schemas.android.com/tools" on <manifest> (the template lacks it; without it manifest merge fails on tools:node). Remove RECORD_AUDIO and WRITE_EXTERNAL_STORAGE. Drop the claim that the plugin injects READ_EXTERNAL_STORAGE.
* [important] 5.2 contract / 6.5.3 PDF: Dart has no way to get cacheDir: no path_provider and no method for it. Directory.systemTemp is probably code_cache (inferred from FlutterLoader passing getCodeCacheDir), which cleanCache would not clean. Specify that the PDF path is built from File(warpResult.path).parent.path (warp writes to cacheDir), or add a `cacheDir` method.
* [important] 6.1 / 6.3 camera vs pushed routes: The editor, save and viewer routes are pushed over the root route, so EscanearTab and its camera stay mounted underneath. Preview, stream and torch keep running during editing and during warp, adding memory pressure on top of 96-400 MB. Specify: stop the stream, turn the torch off and dispose before Navigator.push; re-create after the push future completes.
* [important] 6.1 session ownership: Tapping another SnakeBar tab is not a pop, so PopScope never runs, and the tab body is rebuilt without IndexedStack. Specify that the session lives outside EscanearTab (in the app-level ChangeNotifier), or ask for confirmation on tab change when the session has photos.
* [important] 6.1 PopScope: Replace the per-screen camera PopScope with one root PopScope that handles both tab-back and session discard (see refuted). Optional: add android:enableOnBackInvokedCallback="true" so Android 13-15 behave like 16 (with targetSdk 36 it is already the default on 16).
* [important] 6.3.8 lifecycle: Dispose on hidden/paused, not inactive (the permission dialog, notification shade and share sheet all fire inactive). Serialize controller create/dispose. Retry after CameraAccessDenied only when the app came back from paused/hidden (the user visited Settings), not after the dialog's inactive->resumed, to avoid back-to-back permission prompts. Remove the CameraPreview from the tree (setState) before calling dispose.
* [important] 6.3.2 / 11: Delete setJpegImageQuality(100) and the related risk bullet (see refuted).
* [important] 6.5.4 after save: cleanCache deletes the CAP files, but back from the 'Salvo' state pops to the editor, whose session points at deleted files (preview/warp then fail with not_found). On success: clear the session, and make both 'Concluir' and back do popUntil(first) and set index=0.
* [important] 5.2 warp (coordinates + memory): Decode with ImageDecoder.createSource(File) and setAllocator(ALLOCATOR_SOFTWARE). ImageDecoder applies EXIF itself (from platform knowledge, not run here), so corners stay in upright space and the 'convert to raw sensor space' step and ExifInterface go away. ALLOCATOR_SOFTWARE is required: drawing a HARDWARE bitmap on a software Canvas throws. Do the output rotation inside the same setPolyToPoly by permuting dst corners (corner i -> rect[(i+k)%4], clockwise) instead of a separate rotate, which would allocate a third full-res bitmap. Fill the output white before drawing. Say that rotation is clockwise and that the returned width/height are after rotation (pdf_writer uses them for the page aspect).
* [important] 11 memory >12MP / 9 errors: preferHigherResolutionOverCaptureRate allows high-resolution output sizes, so 50MP (about 400 MB in warp) or larger captures are possible on some devices (inferred). A `memory` failure is deterministic, so the current 'tentar de novo' retries forever. Define a behaviour: check width*height*8 against ActivityManager.MemoryInfo.availMem before allocating; on failure either offer a downscaled save (inSampleSize/targetSize /2, an explicit exception to requirement 6) or skip that photo. Kotlin must catch Throwable (OutOfMemoryError is an Error) so the reply is always sent.
* [important] 5.2 executor: Each executor task must wrap its body in try/catch(Throwable) and call result exactly once, posted to the main thread. Otherwise an OOM or an unexpected exception leaves the Dart Future pending forever ('Processando 2/5' stuck). Map FileNotFoundException to not_found, SecurityException to not_owned, ImageDecoder.DecodeException and PdfRenderer IOException to decode, and other IOException to io.
* [important] 4 Orientação / 5.3: With targetSdk 36, Android 16 ignores screenOrientation and setPreferredOrientations on displays with sw>=600dp (tablets, unfolded foldables). From Android 16 docs; I could not find the opt-out constant in android-36 android.jar, so verify it. There the UI can be landscape while capture stays locked to portraitUp and the sensorOrientation mapping assumes portrait, so the overlay will be misaligned. Either add the temporary opt-out <property android:name="android.window.PROPERTY_COMPAT_ALLOW_RESTRICTED_RESIZABILITY" android:value="true"/> (works only while targeting 36) or document large screens as unsupported.
* [important] 12 Build: Lower the template's org.gradle.jvmargs=-Xmx8G -XX:MaxMetaspaceSize=4G (Gradle plus the Kotlin daemon, which inherits it, plus an emulator can freeze this 30 GB machine). Use e.g. -Xmx3G -XX:MaxMetaspaceSize=1G and kotlin.daemon.jvmargs=-Xmx1536m, and never run builds in parallel. Keep newDsl/builtInKotlin=false: Flutter applies kotlin-android itself (verified).
* [important] 7 detector ordering + 6.3.4 smoothing: Use cyclic hull order rotated to start at min(x+y) (see refuted). Re-sort after rotating into portrait. Before applying EMA, match each corner to the nearest previous corner.
* [minor] 6.4: Use targetHeight=320 for portrait previews (see refuted). Store detected corners separately from edited corners so Redefinir works and swiping in the PageView does not re-run detection over user edits. Show the editor image rotated (RotatedBox) when Girar 90° is applied, or the user cannot see the effect.
* [minor] 4 ABI / 12: Flutter's plugin forces abiFilters [armeabi-v7a, arm64-v8a, x86_64] and camera-core ships 32-bit/x86 .so files. The 'arm64-only' APK will still contain lib/armeabi-v7a with only the CameraX libs, so a 32-bit device installs it and crashes on start (no libflutter.so). Add `ndk { abiFilters.clear(); abiFilters += "arm64-v8a" }` in defaultConfig (it runs after Flutter's apply-time configuration). Inferred from Gradle plugin source plus the aar listing; no APK was built.
* [minor] 5.2 list/save MediaStore: date = DATE_ADDED (seconds) * 1000. Query with RELATIVE_PATH = ? and argument 'Pictures/Papyr/' or 'Documents/Papyr/' (trailing slash; insert with the trailing slash too). Merge the Images and Files results in Kotlin and sort descending. Read the real DISPLAY_NAME after IS_PENDING=0. Take size from the temp file rather than the SIZE column. In delete, a return of 0 rows means not_found. In cleanCache, also delete own orphan pending rows (QUERY_ARG_MATCH_PENDING=MATCH_ONLY). Optionally set DATE_TAKEN=now in ms for gallery ordering.
* [minor] 6.5.5 retry: In Imagens mode, 'Tentar de novo' must resume from the first unsaved photo. Otherwise already-saved photos are saved again and MediaStore names the copies 'x (1).jpg'.
* [minor] 6.3.4 live detection cost: The busy flag does not reduce channel traffic: about 2-3 MB of YUV per frame at PREVIEW size (≤1440x1080) is copied every frame. Subsample straight from planes[0].bytes (no full Y copy). Measure on the low-end device early; the pull model (stop/start stream, only clearAnalyzer/setAnalyzer) is cheap per source and can become the default if needed.
* [minor] 6.6 viewers: Image viewer: `read` sends the full JPEG over the channel (about 10 MB at 12MP is fine; about 40 MB at 50MP means 2-3x Java-heap peaks from StandardMessageCodec). Accept that, or reuse preview(uri, 4096), since cacheWidth 4096 caps the decode anyway. PDF viewer: an InteractiveViewer wrapping a ListView has pan/scroll gesture conflicts, so put an InteractiveViewer per page or zoom per page. Have pdfInfo return per-page [w,h] so placeholders keep their size. Off-screen page requests cannot be cancelled on the serial queue, so drop stale results in Dart.
* [minor] 6.1 / 6.2 edge-to-edge: targetSdk 36 enforces edge-to-edge. The custom SnakeBar must add MediaQuery.viewPadding.bottom (NavigationBar would do this automatically). The camera tab needs a top SafeArea and AnnotatedRegion(SystemUiOverlayStyle.light) over the black background.
* [minor] 12 Release: Release has R8 on and is signed with the debug key from the template. Run the manual checklist on the release APK. Use a stable keystore: a signing-key change forces an uninstall, and per section 11 that loses ownership of every saved file.
* [minor] 6.5 disk: Disk peak in PDF mode is about 3x the output size (warped JPEGs + temp PDF + MediaStore copy). In Imagens mode, delete each warped temp right after its save.
* [minor] 5.2 threading (simplification): Optional: MethodChannel(messenger, "papyr/native", StandardMethodCodec.INSTANCE, messenger.makeBackgroundTaskQueue()) gives a serial background handler without a hand-written executor or Handler. Run share/openAppSettings via runOnUiThread.
* [minor] 6.3.4 isolate lifetime: Spawn the detector isolate in the camera state's init and kill it in dispose. Or use Isolate.run per frame (a few ms of spawn cost, no port or lifecycle code). The editor can use Isolate.run per photo.


## Parte 2: notas de implementação e snippets


######## AREA: Kotlin MethodChannel contract papyr/native (spec 5.2), Android platform APIs only. Native agent. Tested on emulator Medium_Phone_API_36.1 (Android 16 
* Warp corner mapping, tested on emulator for EXIF orientations 1-8. Raw (sensor) pixel space -> upright pixel space for a w x h decoded bitmap:
fun uprightMatrix(o: Int, w: Float, h: Float) = Matrix().apply {
    when (o) {
        2 -> { setScale(-1f, 1f); postTranslate(w, 0f) }
        3 -> { setRotate(180f); postTranslate(w, h) }
        4 -> { setScale(1f, -1f); postTranslate(0f, h) }
        5 -> { setRotate(90f); postScale(-1f, 1f) }                        // transpose
        6 -> { setRotate(90f); postTranslate(h, 0f) }
        7 -> { setRotate(-90f); postScale(-1f, 1f); postTranslate(h, w) }  // transverse
        8 -> { setRotate(-90f); postTranslate(0f, w) }
    }
}
The same mapping as closed forms, for upright-normalized (u,v) -> raw pixels (x,y):
- 1: (u*w, v*h)
- 3: ((1-u)*w, (1-v)*h)
- 6: (v*w, (1-u)*h)
- 8: ((1-v)*w, u*h)
- 2: ((1-u)*w, v*h)
- 4: (u*w, (1-v)*h)
- 5: (v*w, u*h)
- 7: ((1-v)*w, (1-u)*h)
* warp body (tested; Fail(code,msg) is an Exception carrying the PlatformException code):
val orient = ExifInterface(path).getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)
val src = BitmapFactory.decodeFile(path) ?: throw Fail("decode", path)
try {
  val w = src.width.toFloat(); val h = src.height.toFloat()
  val toRaw = Matrix().also { uprightMatrix(orient, w, h).invert(it) }
  val uw = if (orient in 5..8) h else w; val uh = if (orient in 5..8) w else h
  val p = FloatArray(8) { i -> (corners[i] * if (i % 2 == 0) uw else uh).toFloat() }  // TL,TR,BR,BL upright-normalized
  toRaw.mapPoints(p)
  fun d(a: Int, b: Int) = hypot(p[2*a] - p[2*b], p[2*a+1] - p[2*b+1])
  val ow = max(d(0,1), d(3,2)).roundToInt().coerceAtLeast(1)
  val oh = max(d(0,3), d(1,2)).roundToInt().coerceAtLeast(1)
  val m = Matrix()
  if (!m.setPolyToPoly(p, 0, floatArrayOf(0f,0f, ow.toFloat(),0f, ow.toFloat(),oh.toFloat(), 0f,oh.toFloat()), 0, 4)) throw Fail("decode", "degenerate corners")
  val rot = Matrix().apply { setRotate(rotation.toFloat()) }          // 0/90/180/270 clockwise
  val bounds = RectF(0f, 0f, ow.toFloat(), oh.toFloat()).also { rot.mapRect(it) }
  rot.postTranslate(-bounds.left, -bounds.top); m.postConcat(rot)
  val out = Bitmap.createBitmap(bounds.width().roundToInt(), bounds.height().roundToInt(), Bitmap.Config.ARGB_8888)
  try {
    Canvas(out).drawBitmap(src, m, Paint(Paint.FILTER_BITMAP_FLAG))
    src.recycle()
    val f = File(cacheDir, "papyr_${System.nanoTime()}.jpg")
    f.outputStream().buffered(1 shl 16).use { if (!out.compress(Bitmap.CompressFormat.JPEG, 100, it)) throw Fail("io", "compress") }
    return mapOf("path" to f.path, "width" to out.width, "height" to out.height)
  } finally { out.recycle() }
} finally { src.recycle() }
* Channel wiring with the simpler threading (tested serial):
val messenger = flutterEngine.dartExecutor.binaryMessenger
MethodChannel(messenger, "papyr/native", StandardMethodCodec.INSTANCE, messenger.makeBackgroundTaskQueue()).setMethodCallHandler { call, result ->
  try { val out = handle(call); if (out === NOT_IMPL) result.notImplemented() else result.success(out) }
  catch (e: Throwable) { result.error(errorCode(e), e.toString(), null) }
}
errorCode:
- Fail -> its code
- OutOfMemoryError -> "memory"
- FileNotFoundException -> "not_found"
- SecurityException -> "not_found" (see refuted not_owned)
- else -> "io"
If the spec's Executor version is kept instead: worker.execute { val out = try { handle(call) } catch (e: Throwable) { e }; main.post { ... } }. This was verified too.
* preview, BitmapFactory version (tested):
val o = BitmapFactory.Options().apply { inJustDecodeBounds = true }; BitmapFactory.decodeFile(path, o)
if (o.outWidth <= 0) throw Fail("decode", path)
var sample = 1; while (max(o.outWidth, o.outHeight) / (sample*2) >= maxSide) sample *= 2
val raw = BitmapFactory.decodeFile(path, BitmapFactory.Options().apply { inSampleSize = sample }) ?: throw Fail("decode", path)
val orient = <exif>
val m = uprightMatrix(orient, raw.width.toFloat(), raw.height.toFloat())
val s = minOf(1f, maxSide.toFloat() / max(raw.width, raw.height)); m.postScale(s, s)
val small = Bitmap.createBitmap(raw, 0, 0, raw.width, raw.height, m, true)   // createBitmap ignores translation
if (small !== raw) raw.recycle()
Return width/height = o.outHeight/o.outWidth swapped when orient in 5..8.
ImageDecoder alternative (tested):
var w = 0; var h = 0
val b = ImageDecoder.decodeBitmap(ImageDecoder.createSource(File(path))) { d, info, _ ->
  w = info.size.width; h = info.size.height
  val s = minOf(1f, maxSide.toFloat() / max(w, h))
  d.setTargetSize((w*s).toInt(), (h*s).toInt())
  d.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
}
Here w/h are already upright full dims.
* save (tested):
val pdf = mime == "application/pdf"
val coll = if (pdf) MediaStore.Files.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY) else MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
val uri = contentResolver.insert(coll, ContentValues().apply {
  put(MediaColumns.DISPLAY_NAME, name); put(MediaColumns.MIME_TYPE, mime)
  put(MediaColumns.RELATIVE_PATH, if (pdf) "Documents/Papyr" else "Pictures/Papyr"); put(MediaColumns.IS_PENDING, 1)
}) ?: throw Fail("io", "insert failed")
try {
  contentResolver.openOutputStream(uri)!!.use { o -> File(path).inputStream().use { it.copyTo(o, 1 shl 16) } }
  contentResolver.update(uri, ContentValues().apply { put(MediaColumns.IS_PENDING, 0) }, null, null)
} catch (e: Throwable) { contentResolver.delete(uri, null, null); throw e }
Then re-query the uri for _ID, DISPLAY_NAME (the real, possibly renamed name), MIME_TYPE, SIZE, DATE_ADDED.
* list (tested):
contentResolver.query(MediaStore.Files.getContentUri(VOLUME_EXTERNAL_PRIMARY), arrayOf(_ID, DISPLAY_NAME, MIME_TYPE, SIZE, DATE_ADDED), "relative_path IN (?, ?)", arrayOf("Pictures/Papyr/", "Documents/Papyr/"), "date_added DESC, _id DESC")
Per row: uri = ContentUris.withAppendedId(if (mime == "application/pdf") filesUri else imagesUri, id); date = date_added*1000. Note the trailing slash in RELATIVE_PATH on query, but no slash on insert.
* thumbnail / pdfInfo / pdfPage (tested):
fun <T> pdf(uri: Uri, f: (PdfRenderer) -> T): T = PdfRenderer(contentResolver.openFileDescriptor(uri, "r") ?: throw FileNotFoundException(uri.toString())).use(f)
Render a page: r.openPage(i).use { p -> val b = Bitmap.createBitmap(width, max(1, width * p.height / p.width), ARGB_8888); b.eraseColor(Color.WHITE); p.render(b, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY); compress JPEG 90 }
Image thumbnail: contentResolver.loadThumbnail(uri, Size(size, size), null) then JPEG compress. Recycle bitmaps after compress.
* share (tested cross-app):
val send = if (uris.size == 1) Intent(Intent.ACTION_SEND).putExtra(Intent.EXTRA_STREAM, uris[0]) else Intent(Intent.ACTION_SEND_MULTIPLE).putParcelableArrayListExtra(Intent.EXTRA_STREAM, ArrayList(uris))
send.type = mime   // use "*/*" for mixed image+pdf
send.clipData = ClipData.newRawUri(null, uris[0]).apply { uris.drop(1).forEach { addItem(ClipData.Item(it)) } }
send.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
startActivity(Intent.createChooser(send, null))
Works from the TaskQueue thread. The Activity context is required (FlutterActivity is one).
* Probe-only gotchas for whoever runs the device next:
- The emulator's /data was 97% full and installs failed with 'Requested internal only, but not enough space'. I uninstalled the throwaway probes left over from the frozen run (com.pedroalves.kprobe, com.pedroalves.kreceiver), my own nprobe and recv, and removed /sdcard/Pictures/Papyr and /sdcard/Documents/Papyr. The user's own apps were not touched. Check `adb shell dumpsys diskstats | grep Data-Free` before installing.
- `flutter build` launched via a backgrounded shell exited 255 with no output (snap flutter); run it in the foreground.
- The Flutter template gradle.properties sets org.gradle.jvmargs=-Xmx8G; the probe used -Xmx2g plus workers.max=3. An incremental debug build took 5-30 s.
- In the Android 16 chooser, third-party targets only show after expanding the sheet (swipe up).
- Every Paint has FILTER_BITMAP_FLAG by default on API 28+, so A/B quality tests need an explicit isFilterBitmap=false.


######## AREA: Section 7: the pure-Dart quad detector, and section 6.3 step 4: whether the live pipeline is feasible. All runs were on the desktop: Dart 3.12.2, AOT 
* Threshold: `final med = pct(mag, 0.5); final hi = math.max(25.0, 4 * med); final lo = 0.3 * hi;`. Build the magnitude histogram with 1500 int bins (the maximum L2 Sobel value on 8-bit input is about 1442) over interior pixels only.
* Hysteresis and NMS: strong if nms > hi, weak if nms > lo, both strict. For NMS keep v > m[i+off] && v >= m[i-off], an asymmetric tie-break so plateaus are not doubled. Direction bins: |gy| <= 0.414|gx| -> horizontal, |gy| >= 2.414|gx| -> vertical, else (gx^gy) >= 0 -> the 'backslash' diagonal (offset w+1), otherwise offset w-1.
* Hull input: during labeling keep only the leftmost and rightmost pixel of each row (rowMin/rowMax arrays with a per-component row stamp). Encode as x*4096+y, sort the ints and run the monotone chain on at most 2*h points. The result has positive shoelace area, which is TL->TR->BR->BL in image coordinates.
* Cyclic ordering: if area > 0 use idx [0,1,2,3], else [0,3,2,1]. Start at argmin(x+y), then take the 4 points cyclically.
* Contrast support for one side (x0,y0)->(x1,y1): d = unit direction, n = (dy,-dx) flipped to point away from the centroid. For t in [0.1L, 0.9L] step 1: dd = blur[p - 3n] - blur[p + 3n]; pos += dd >= 8, neg += dd <= -8; support = max(pos,neg)/tot. Skip samples outside the frame; with tot < 8, treat the side as a border side.
* Region candidates: run the same labeling on the dilated map with want == 0 and 4-connectivity (8-connectivity would leak diagonally through 1-px gaps). The background component's hull is the whole frame and gets rejected by the more-than-2-border-sides rule.
* Outward offset for a positive-orientation quad (miter): for vertex i, a = unit(v_i - v_{i-1}), b = unit(v_{i+1} - v_i), n1 = (a.y, -a.x), n2 = (b.y, -b.x); v' = v + d * (n1 + n2) / (1 + n1.n2) with d = 2 px.
* Frame-cut fix: run it only on a 5-point DP result. For the adjacent vertices i, i+1 on the same border, intersect line(v_{i-1}, v_i) with line(v_{i+2}, v_{i+1}). Accept only if the point is beyond that border and less than 0.3*dimension outside, then return [v_{i+2}, v_{i+3}, v_{i-1}, P]. Clamp the normalized output to 0..1 at the end.
* Live subsample, run on the main isolate: precompute xt[x] = x*w ~/ 320 and yt[y] = y*h ~/ 240 (recompute when w or h changes); `o[y*ow+x] = (p[r+i] + p[r+i+1] + p[r+stride+i] + p[r+stride+i+1] + 2) >> 2` with r = yt[y]*bytesPerRow and i = xt[x]. Rows read stay <= h-4 at a 4.5 step, so the unpadded last row is never touched.
* EMA alignment: `int best = 0; for (k in 0..3) sum of |new[(j+k)%4] - prev[j]|^2 -> pick min k; rotate new by k; then prev = 0.5*prev + 0.5*new`. Do this after re-ordering in portrait space.
* Sensor-to-portrait mapping for sensorOrientation 90: (x, y) -> (1 - y, x). It keeps the clockwise order, but the vertex that was BL becomes TL, so run orderCyclic again after mapping.
* If the region pass is too slow on the device: regions-only with the 2 px offset scored the same as edge+regions on held-out data (one fewer rot45 pass, lower median error) and drops one of the two labeling passes (about -1 ms on the desktop). Other cheap speedups: L1 magnitude instead of sqrt, and reusing buffers across frames (the prototype allocates about 10 typed arrays per call).
* The editor path in section 6.4 (instantiateImageCodec with targetWidth 320) already gives a filtered downscale, which matches the 2x2/box input that tested best, so use the same detector constants there.
* This is all synthetic: there is no real-photo validation and no device timing. First on-device checks: shadow edges crossing the page (seen as a 'wrong' result in realWhite seed 14, where the bottom side snapped to the shadow line), glossy glare, and the stream fps with the plugin's per-frame 3-plane copy.


######## AREA: Minimal PDF writer (spec section 8, pdf_writer.dart + pdf_writer_test.dart). Final prototype: /tmp/claude-1000/-var-www-projetos-pessoal-scanner/d545c
* Signature: `Future<void> writePdf(String outPath, List<String> jpegPaths)`, top-level function, no class. Also export `(int, int, int) jpegInfo(Uint8List head)` returning (width, height, components) so it can be tested.
* Object numbering: 1 = Catalog `<< /Type /Catalog /Pages 2 0 R >>`; 2 = Pages `<< /Type /Pages /Kids [3 0 R 6 0 R ...] /Count N >>`. Kids are known up front because N is known. For page i (0-based), n = 3+3i: n = Page, n+1 = Contents, n+2 = Image. Total objects 2+3N; xref has 3+3N entries; trailer /Size 3+3N. Objects are written strictly in order 1..2+3N, so offsets[] fills in order.
* Header bytes: `%PDF-1.4` LF then `%` E2 E3 CF D3 LF, 15 bytes, written as raw bytes: [0x25,0x50,0x44,0x46,0x2D,0x31,0x2E,0x34,0x0A,0x25,0xE2,0xE3,0xCF,0xD3,0x0A]. Never use sink.write(String) for these bytes: the UTF-8 encoding would turn 4 bytes into 8 and break the byte count. All other text goes through ascii.encode, which throws on non-ASCII, so byte count == char count. Do not use IOSink.write.
* Object text, with LF as the only EOL: 'k 0 obj' LF, then the dict, LF 'endobj' LF. Page dict: `<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595.28 H] /Resources << /XObject << /Im0 {n+2} 0 R >> >> /Contents {n+1} 0 R >>`. No /ProcSet (obsolete) and no /Info. If a /Title is ever added, non-ASCII text needs UTF-16BE with BOM, and ascii.encode will throw as a guard.
* H = (595.28 * h / w).toStringAsFixed(2), from SOF dims. Use the SAME string in MediaBox and in the content stream. toStringAsFixed never emits exponent notation below 1e21, whereas double.toString can give e.g. 1e-7, which is invalid in PDF. Acrobat's page-size limit is 14400 pt, reached only at an aspect ratio above 24:1. Not clamped (YAGNI).
* Content stream: content = 'q 595.28 0 0 $H 0 0 cm /Im0 Do Q'. Write `<< /Length ${content.length} >>` LF 'stream' LF content LF 'endstream' LF 'endobj' LF. The LF before endstream is NOT counted in /Length.
* Image object: `<< /Type /XObject /Subtype /Image /Width $w /Height $h /ColorSpace $cs /BitsPerComponent 8 /Filter /DCTDecode /Length $len >>` LF 'stream' LF, then the raw JPEG, then LF 'endstream' LF 'endobj' LF. 'stream' must be followed by LF or CRLF, never a bare CR. len = file length taken from the same RandomAccessFile used to read the 64 KB SOF header (open, length(), read(65536), close in finally).
* Copy the JPEG with `await sink.addStream(jpg.openRead().map((c) { pos += c.length; return c; }))`, then `if (pos - start != len) throw FileSystemException('JPEG changed while copying', path)`. Gotcha: never call sink.add/flush/close while addStream is pending (StateError 'StreamSink is bound to a stream'); always await addStream first.
* xref: xrefOffset = pos; then 'xref' LF '0 {count}' LF '0000000000 65535 f ' LF, then per object `${o.toString().padLeft(10, '0')} 00000 n ` + LF. Each entry is exactly 20 bytes: 10 digits, SP, 5 digits, SP, n/f, and a 2-byte EOL, here SP+LF (CRLF is also legal; bare LF = 19 bytes is wrong, and only gs in strict mode notices). Then 'trailer' LF '<< /Size {count} /Root 1 0 R >>' LF 'startxref' LF '{xrefOffset}' LF '%%EOF' LF. 10 digits allow offsets up to about 9.3 GB.
* Error handling: `final sink = file.openWrite(); sink.done.ignore();`. Then try { ... await sink.close(); } catch (_) { await sink.close().catchError((_) {}); await file.delete().catchError((_) => file); rethrow; }. Without done.ignore(), an open failure or ENOSPC that happens between addStream calls is an unhandled async error (verified).
* jpegInfo(b): require b[0]==0xFF && b[1]==0xD8. Then i = 2; loop while i+9 < b.length: require b[i]==0xFF; m = b[i+1]; if m == 0xFF, i++ (fill byte); else if m in 0xC0..0xCF except C4/C8/CC, return (b[i+7]<<8|b[i+8], b[i+5]<<8|b[i+6], b[i+9]) = (width, height, components); else i += 2 + (b[i+2]<<8|b[i+3]). Throw FormatException if no SOF. 64 KB is plenty for Bitmap.compress output (SOF within the first ~600 bytes). A camera JPEG with a large EXIF thumbnail could exceed it, but those must never be fed to the writer anyway.
* Colour space: switch (comps) { 1 => '/DeviceGray', 3 => '/DeviceRGB', _ => throw FormatException('JPEG with $comps components', path) }. Bitmap.compress of ARGB_8888 is 3-component baseline YCbCr (inferred, not run on a device). Progressive (SOF2) also embeds and renders fine in poppler and gs (verified).
* Memory and time: streaming keeps RSS flat (16 MB native exe for 200 MB of output). If someone switches to readAsBytes, they must `await sink.flush()` per page or all pages get queued; that variant measured 64-75 MB. Disk: the cache PDF plus the MediaStore copy need about 2x the PDF size transiently (300 MB PDF -> 600 MB). ENOSPC surfaces as FileSystemException and the partial file is deleted.
* pdf_writer_test.dart (no external tools). Imports: dart:convert, dart:io, dart:typed_data, package:flutter_test/flutter_test.dart, package:papyr/pdf_writer.dart. setUp creates Directory.systemTemp.createTempSync('papyr_pdf'); tearDown deletes it recursively. Helper: `String put(name, bytes) => (File('${dir.path}/$name')..writeAsBytesSync(bytes)).path`. Use test(), not testWidgets(), because real async I/O hangs in FakeAsync.
* Test fixtures: (a) a real 287-byte 1x1 baseline RGB JPEG, verified to decode in PIL and render through the PDF in poppler and gs: `final tinyJpeg = base64Decode('/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDABALDA4MChAODQ4SERATGCgaGBYWGDEjJR0oOjM9PDkzODdASFxOQERXRTc4UG1RV19iZ2hnPk1xeXBkeFxlZ2P/2wBDARESEhgVGC8aGi9jQjhCY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2P/wAARCAABAAEDASIAAhEBAxEB/8QAFQABAQAAAAAAAAAAAAAAAAAAAAX/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/8QAFQEBAQAAAAAAAAAAAAAAAAAABQb/xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oADAMBAAIRAxEAPwCKALXj/9k=');`. (b) a fake JPEG generator, enough because the writer only reads SOF and copies bytes: `Uint8List fakeJpeg(int w, int h, [int comps = 3]) => Uint8List.fromList([0xFF,0xD8, 0xFF,0xE0,0x00,0x04,0x4A,0x46, 0xFF,0xC0,0x00,8+3*comps,8,h>>8,h&255,w>>8,w&255,comps, for (var c = 1; c <= comps; c++) ...[c,0x11,0], 0xFF,0xD9]);`.
* Test 1: expect(jpegInfo(tinyJpeg), (1, 1, 3)).
* Test 2: write [tinyJpeg, fakeJpeg(40,400), fakeJpeg(64,48,1)] and set s = latin1.decode(bytes), so string index == byte offset and plain RegExp/indexOf work. Then check: s startsWith '%PDF-1.4' + LF + '%'; bytes 10..13 >= 128; parse startxref with RegExp(r'startxref\n(\d+)\n%%EOF\n$'); RegExp(r'xref\n0 (\d+)\n').matchAsPrefix(s, sx) is non-null; count == 3+3N; entry 0 == '0000000000 65535 f ' + LF; for k in 1..count-1, the 20-byte entry matches ^\d{10} 00000 n \n$ and s.startsWith('$k 0 obj\n', offset); trailer startsWith '<< /Size $n /Root 1 0 R >>'; for every RegExp(r'/Length (\d+) >>\nstream\n') match, s.startsWith('\nendstream\n', end + L); for each jpg, at = s.indexOf(latin1.decode(jpg)) and s.substring(0, at) endsWith '/Length ${jpg.length} >>' + LF + 'stream' + LF; s contains '/MediaBox [0 0 595.28 5952.80]', 'q 595.28 0 0 5952.80 0 0 cm /Im0 Do Q', '/Width 40 /Height 400 /ColorSpace /DeviceRGB' and '/Width 64 /Height 48 /ColorSpace /DeviceGray'.
* Tests 3-5: expectLater(writePdf(out, [tiny, fakeJpeg(8,8,4)]), throwsFormatException) and the out file does not exist afterwards. A missing input path gives throwsA(isA<FileSystemException>()) and no file left. Output '${dir.path}/no/such/dir/o.pdf' gives throwsA(isA<FileSystemException>()); this is the regression test for done.ignore(), and the test framework flags the unhandled error if the fix is removed.
* Not verified: Android PdfRenderer (pdfium) and external Android viewers opening these files, and write speed on phone flash. Add to the manual device checklist: open a 20-page PDF in the app viewer and in an external app (already in spec section 10).


######## AREA: Camera screen correctness (spec 6.3): camera 0.12.1 + camera_android_camerax 0.7.5+1 + camera_platform_interface 2.15.0, read from ~/.pub-cache/hosted
* Upright sampler (verified by luma_check.dart). It returns the image the detector should see, and its normalized coords map 1:1 onto CameraPreview's child:
```dart
(Uint8List, int, int)? uprightLuma(Uint8List y, int rowStride, int w, int h, int sensorDeg, {int maxSide = 320}) {
  if (y.length < (h - 1) * rowStride + w) return null; // malformed frame
  final s = min(1.0, maxSide / max(w, h));
  final sw = max(1, (w * s).round()), sh = max(1, (h * s).round());
  final swap = sensorDeg % 180 != 0;
  final ow = swap ? sh : sw, oh = swap ? sw : sh;
  final out = Uint8List(ow * oh);
  for (var oy = 0; oy < oh; oy++) {
    for (var ox = 0; ox < ow; ox++) {
      final (bx, by) = switch (sensorDeg) {
        90 => (oy, sh - 1 - ox),
        270 => (sw - 1 - oy, ox),
        180 => (sw - 1 - ox, sh - 1 - oy),
        _ => (ox, oy),
      };
      out[oy * ow + ox] = y[(by * h ~/ sh) * rowStride + (bx * w ~/ sw)];
    }
  }
  return (out, ow, oh);
}
// call: final p = img.planes[0]; uprightLuma(p.bytes, p.bytesPerRow, img.width, img.height, c.description.sensorOrientation)
// ponytail: assumes display rotation 0 (phone portrait); tablets need (sensor - displayRotation)
```
* If you instead keep detection on the raw landscape buffer, the point mapping is:
```dart
(double, double) bufferToChild(double u, double v, int sensorDeg) => switch (sensorDeg) {
  90 => (1 - v, u), 270 => (v, 1 - u), 180 => (1 - u, 1 - v), _ => (u, v) };
```
After mapping, re-sort the corners in screen space (TL = min x+y, ...), because labels assigned in landscape space are rotated.
* Overlay. The child is outside the RotatedBox and gets the full preview box, so draw in plain normalized coords:
```dart
ColoredBox(color: Colors.black, child: Center(child: CameraPreview(c, child: CustomPaint(painter: QuadPainter(_quad)))))

class QuadPainter extends CustomPainter {
  QuadPainter(this.q); final List<double>? q; // 8 doubles TL,TR,BR,BL, upright-normalized
  @override void paint(Canvas canvas, Size s) {
    final q = this.q; if (q == null) return;
    final p = Path()..moveTo(q[0] * s.width, q[1] * s.height);
    for (var i = 2; i < 8; i += 2) p.lineTo(q[i] * s.width, q[i + 1] * s.height);
    canvas.drawPath(p..close(), Paint()..style = PaintingStyle.stroke..strokeWidth = 3..color = const Color(0xFF00E676));
  }
  @override bool shouldRepaint(QuadPainter o) => o.q != q;
}
```
* Lifecycle skeleton covering the gotchas found in source:
```dart
Future<void> _lastDispose = Future.value(); // top-level: platform is a singleton, never overlap dispose/create

void _stop() { // call from inactive, before pushing the editor; in State.dispose skip the setState
  final c = _c; if (c == null) return;
  setState(() => _c = null);            // drop CameraPreview first: buildPreview() throws on a disposed controller
  _lastDispose = _lastDispose.then((_) => c.dispose()).catchError((_) {});
}

Future<void> _start() async {
  if (_c != null || _starting) return;
  _starting = true;
  try {
    await _lastDispose;
    final back = (await availableCameras()).firstWhere((d) => d.lensDirection == CameraLensDirection.back);
    final c = CameraController(back, ResolutionPreset.max, enableAudio: false, imageFormatGroup: ImageFormatGroup.yuv420);
    try { await c.initialize(); } catch (_) { _lastDispose = _lastDispose.then((_) => c.dispose()); rethrow; }
    await c.lockCaptureOrientation(DeviceOrientation.portraitUp);
    await c.setFlashMode(FlashMode.off);                 // resets plugin's stale torchEnabled
    if (_torchOn) await c.setFlashMode(FlashMode.torch);
    if (!mounted) { _lastDispose = _lastDispose.then((_) => c.dispose()); return; }
    setState(() { _c = c; _err = null; });
    await c.startImageStream((img) => _onFrame(c, img));
  } on CameraException catch (e) {
    if (e.code != 'CameraPermissionsRequestOngoing' && mounted) setState(() => _err = e.code); // 'CameraAccessDenied'
  } finally { _starting = false; }
}

@override
void didChangeAppLifecycleState(AppLifecycleState s) {
  if (s == AppLifecycleState.inactive) {
    if (_c?.value.isInitialized ?? false) _stop();     // not while initialize() waits on the permission dialog
  } else if (s == AppLifecycleState.resumed) {
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return; // editor/save route on top
    if (_err == 'CameraAccessDenied' && !_openedSettings) return; // no loop when permanently denied
    _openedSettings = false;
    _start();
  }
}

void _onFrame(CameraController c, CameraImage img) {
  if (_busy || !identical(c, _c) || c.value.isTakingPicture) return; // frames can arrive after dispose()
  final p = img.planes[0];
  final g = uprightLuma(p.bytes, p.bytesPerRow, img.width, img.height, c.description.sensorOrientation);
  if (g == null) return;
  _busy = true;
  _workerPort.send(g); // reply handler: _busy = false; EMA; setState(_quad)
}

Future<void> _openEditor() async {
  _stop(); // torch + stream off while editor/save are on top
  await Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(builder: (_) => const CropScreen()));
  if (mounted) _start();
}
```
The 'Abrir ajustes' button sets `_openedSettings = true` before calling native openAppSettings. 'Tentar novamente' calls `_start()`.
* takePicture: guard double taps with `if (c.value.isTakingPicture) return;`, catch CameraException and show the 'Falha ao capturar' snackbar. There is no need to stop the image stream. The busy check above already skips detection during capture.
* Camera-in-use / device policy errors do NOT throw from initialize(). They arrive asynchronously in controller.value.errorDescription, and only the FIRST error (the controller listens with .first). If 6.3 wants a message for 'camera busy', watch value.errorDescription in the ValueListenableBuilder.
* Session singleton (scan/session.dart):
```dart
final session = Session(); // ponytail: process-lifetime; lost if Android kills the process (CAP files then removed by cleanCache at next cold start)
class Session extends ChangeNotifier {
  final photos = <Photo>[]; // Photo: path, corners?, rotation
  void add(Photo p) { photos.add(p); notifyListeners(); }
  void removeAt(int i) { photos.removeAt(i); notifyListeners(); }
  void clear() { photos.clear(); notifyListeners(); }
}
```
Only call cleanCache at cold start and after a successful save, NEVER on resume, because the in-memory session references CAP*.jpg files.
* Manifest (android/app/src/main/AndroidManifest.xml):
```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:tools="http://schemas.android.com/tools">
    <uses-permission android:name="android.permission.RECORD_AUDIO" tools:node="remove" />
    <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" tools:node="remove" />
```
The native agent should confirm with build/app/intermediates/merged_manifests/release/.../AndroidManifest.xml. I did not build it.
* One-time debug log for the overlay assumption: `if ((img.width / img.height - c.value.aspectRatio).abs() > 0.01) debugPrint('analysis ${img.width}x${img.height} vs preview ${c.value.previewSize}: overlay misaligned');`
* Pull model, if needed: stopImageStream() inside onFrame and startImageStream() when the isolate replies. It is cheap (clearAnalyzer, then isBound + setAnalyzer, with no session reconfiguration). Before each start, check `identical(c, _c)` and `!c.value.isStreamingImages`, because both stop and start throw on a disposed controller or when the state is wrong.
* Tooling gotcha for other agents: /snap/bin/dart cannot see files under /tmp (snap-private /tmp). `dart run` there exits 0 with NO output. Use ~/snap/flutter/common/flutter/bin/cache/dart-sdk/bin/dart for scratch scripts under /tmp.
* Not verified, for the native agent: camera_android_camerax 0.7.2+1 'Migrates to Built-in Kotlin to support AGP 9'. Its build.gradle.kts applies only com.android.library and has a bare kotlin{} block, while the Flutter 3.44 template keeps android.builtInKotlin=false (spec 12). The first real build should confirm the plugin compiles with that flag. The ~/.gradle cache does contain CameraX 1.6.2 transforms from some earlier build.


######## AREA: Spec critique: user flows and requirements coverage (Papyr design spec 2026-10-17). No code written, nothing touched under /var/www/projetos/pessoal/s
* One back handler at the root Scaffold, because every PopScope in a route gets onPopInvoked (routes.dart:2045). Logic: canPop = (tab == 0). In the handler: if tab == 1 and the session has photos, confirm, then session.clear(), cleanCache(), tab = 0; otherwise tab = 0. The editor and save routes have their own PopScope, which does not discard the session.
* Camera serialization: one static Future<void> _cameraGate = Future.value(). Before creating a controller, `await _cameraGate`. When disposing, `_cameraGate = controller.dispose()`. Reason: the plugin's dispose(cameraId) ignores the id and calls unbindAll/releaseSurfaceProvider on shared fields (android_camera_camerax.dart:516).
* Lifecycle: dispose on AppLifecycleState.paused/hidden, not inactive (the permission dialog and the notification shade only cause inactive). Recreate on resumed only if mounted, tab == Escanear and ModalRoute.of(context)!.isCurrent. Add a RouteObserver to MaterialApp.navigatorObservers and use RouteAware didPushNext to dispose and didPopNext to recreate.
* Permission retry flag: set _openedSettings = true when 'Abrir ajustes' is tapped. On resumed, retry only if the flag is set, then clear it. If CameraPermissionsRequestOngoing arrives, ignore it.
* Session model (plain Dart class at the root, with notifyListeners or a callback). Each photo holds path, Rect/8 doubles? detected (computed once), corners (user, starting as detected or full image), rotation, and savedUri? (for resuming after a partial save). Never re-run detection when the PageView rebuilds.
* On save success: session.clear() and cleanCache() BEFORE showing 'Salvo'. Keep the saved URIs locally in the save screen for Compartilhar. PopScope(canPop:false) on the done state does the same as Concluir: Navigator.popUntil((r) => r.isFirst); tab = 0; library.refresh().
* Name sanitizer (worth one small test): n = name.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '').trim(); remove leading dots; if empty, use the default name; TextField maxLength about 100. Never use the name in cache paths: warp output is papyr_w_<i>.jpg and the PDF temp is papyr_out.pdf (both match cleanCache's papyr_* pattern).
* PDF writer API that takes pages one at a time (begin(IOSink), addPage(path, w, h), finish()) so each warped JPEG is deleted right after it is appended. This is still testable with the existing pdf_writer_test checks (xref offsets, startxref, JPEG bytes intact).
* Detector input in the editor: instantiateImageCodec(bytes, targetWidth: w >= h ? 320 : null, targetHeight: h > w ? 320 : null), so the longer side is 320 px or less as section 7 requires.
* SnakeBar: pad by MediaQuery.viewPaddingOf(context).bottom (edge-to-edge is forced at targetSdk 36).
* Shutter: `onPressed: controller.value.isTakingPicture ? null : shoot`. Disable Concluir when the session is empty. Block repeated taps on navigation buttons with an _busy flag.
* After `flutter create`: delete cupertino_icons from pubspec.yaml, change android:label from 'papyr' to 'Papyr', set minSdk = 30 (template default is 24). Dates and sizes are formatted by hand with a comma decimal, since intl is not available.
* Only the native agent may run builds. Check the merged release manifest with `aapt2 dump permissions <apk>`: expect CAMERA only, with no INTERNET and no RECORD_AUDIO.
* Earlier probe directories (scratchpad/probe, cvbench, pdftest) are gone after the crash. Any earlier device claims (MediaStore channel on API 36.1) have to be re-run by the native agent before the plan relies on them.


######## AREA: Spec critique: technical consistency and Android/Flutter correctness (Papyr design spec 2026-10-17). Note: the earlier probe dirs (probe, cvbench, pdf
* Kotlin warp (only Android APIs). `val src = ImageDecoder.decodeBitmap(ImageDecoder.createSource(File(path))) { d, _, _ -> d.allocator = ImageDecoder.ALLOCATOR_SOFTWARE }` gives an EXIF-upright bitmap. `p[i] = c[i] * (if (i%2==0) W else H)`. `w = max(|TL-TR|, |BL-BR|)`, `h = max(|TL-BL|, |TR-BR|)` in pixels. `(ow,oh) = if (rot%180==0) w to h else h to w`. `rect = [0,0, ow,0, ow,oh, 0,oh]`, `k = rot/90`, `dst[2i..2i+1] = rect[2*((i+k)%4)..]`. `check(m.setPolyToPoly(p,0,dst,0,4))`. `Canvas(out).drawColor(WHITE)` then `drawBitmap(src, m, Paint(Paint.FILTER_BITMAP_FLAG))`. `src.recycle()`, then `out.compress(JPEG,100, BufferedOutputStream(...))`. Return the rotated ow/oh.
* If BitmapFactory is kept instead of ImageDecoder, the upright->raw normalized mapping (verified with dart run) is: EXIF 6 (90 CW): raw=(uy, 1-ux). EXIF 3: (1-ux, 1-uy). EXIF 8 (270): (1-uy, ux). Others: identity.
* Live overlay mapping from sensor-buffer normalized space to portrait: sensorOrientation 90 gives (1-y, x); 270 gives (y, 1-x). Then re-sort the corners. Width and height come from each CameraImage. Y plane: rows = min(height, bytes.length ~/ bytesPerRow); pixelStride is 1.
* preview(path, maxSide): ImageDecoder with OnHeaderDecodedListener. info.size is already upright full-res and gives the returned width/height. setTargetSize(scaled) and ALLOCATOR_SOFTWARE, then compress JPEG ~90. The same code with createSource(contentResolver, uri) can back a viewer decode if `read` is dropped.
* Channel types: read corners with `(call.argument<List<*>>("corners")!!).map { (it as Number).toDouble() }`, because the Dart default list [0,0,1,0,1,1,0,1] written with int literals arrives as Integer. Send pdfPage width as `(w*dpr).round()`. On the Dart side cast results via `(r as Map).cast<String,Object?>()`, since StandardMessageCodec yields Map<Object?,Object?>.
* Root back handling: `PopScope(canPop: index==0 && !session.hasPhotos, onPopInvokedWithResult: (didPop,_) { if (didPop) return; if (index==1 && session.hasPhotos) confirmDiscard(); else setState(()=>index=0); })`.
* Camera lifecycle serialization: `static Future<void> _cam = Future.value(); _cam = _cam.then((_) async { await old?.dispose(); ... create/init new ... });`. Remove CameraPreview from the tree before dispose. After each await check `mounted && identical(c, _controller)`. Order after initialize: lockCaptureOrientation(portraitUp), setFlashMode(off or torch), startImageStream. No setJpegImageQuality.
* Dart PDF path: `final cacheDir = File(warped.first.path).parent.path;` (Kotlin writes warp output to cacheDir). Do not use Directory.systemTemp.
* pdf_writer: write the header bytes '%PDF-1.4\n%\xE2\xE3\xCF\xD3\n' with sink.add(bytes), not sink.write, which UTF-8 encodes. Count offsets manually. Copy each JPEG with `await sink.addStream(File(p).openRead())` and add File.lengthSync() to the counter. Format numbers with toStringAsFixed(2). Each xref line is exactly 20 bytes ('%010d 00000 n \n'), and entry 0 is '0000000000 65535 f \n'. Each Page needs /Resources << /XObject << /Im0 n 0 R >> >>.
* MediaStore save: insert into MediaStore.Images.Media.getContentUri(VOLUME_EXTERNAL_PRIMARY) or MediaStore.Files.getContentUri(VOLUME_EXTERNAL_PRIMARY) with DISPLAY_NAME, MIME_TYPE, RELATIVE_PATH 'Pictures/Papyr/' or 'Documents/Papyr/', IS_PENDING=1. Copy, then update IS_PENDING=0, then query DISPLAY_NAME and DATE_ADDED. On any failure delete the row. A null from insert() means io.
* Manifest additions: `xmlns:tools` on <manifest>; `<uses-permission android:name="android.permission.RECORD_AUDIO" tools:node="remove"/>` and the same for WRITE_EXTERNAL_STORAGE; `android:screenOrientation="portrait"` on the activity. Optionally android:enableOnBackInvokedCallback="true" on <application>, and the Android 16 large-screen opt-out property if landscape is not handled. Keep the template's configChanges.
* app/build.gradle.kts defaultConfig: `minSdk = 30` and `ndk { abiFilters.clear(); abiFilters += "arm64-v8a" }`. gradle.properties: lower org.gradle.jvmargs (e.g. -Xmx3G -XX:MaxMetaspaceSize=1G) and add kotlin.daemon.jvmargs=-Xmx1536m. Keep android.newDsl=false and android.builtInKotlin=false.
* Native agent should verify on the emulator (not verified here): ImageDecoder EXIF auto-orientation on a CameraX CAP file; the actual ImageAnalysis CameraImage size with ResolutionPreset.max; insert into Files with Documents/Papyr; DISPLAY_NAME dedup naming; `unzip -l` of the release APK for lib/ ABIs; merged manifest has no INTERNET/RECORD_AUDIO.
