# AGENT.md — Yapay zekâ ajanları için proje rehberi

Bu dosya, bu klasörde çalışacak kodlama ajanları (Claude Code, Codex vb.) için yazıldı. Ayrıntılı teknik
günlük ve doğrulanmış bulgular `MODLOG.md`'de; burada kurallar, mimari, iş akışı ve tuzaklar var.
**İşe başlamadan önce `MODLOG.md`'yi oku.**

## Proje özeti

- Oyun: **Spider-Man 2 (2004, PC)**, Unreal Engine 2 (paket sürümü 126), çalıştırılabilir dosya `System/Webhead.exe` (x86).
- Amaç: oyunun tüm mekaniklerini **Marvel's Spider-Man (Insomniac)** tarzıyla değiştirmek: yürüme, 3. şahıs kamera,
  fizik tabanlı ağla sallanma, dövüş, ağ atma, tuş düzeni. Eski sistemin üstüne yama değil, **tam değiştirme**.
- Mekaniklerin referansı: `örnekhtml/src` (Three.js oyunu: `player.js`, `camera.js`, `input.js`, `enemies.js`).
  Kullanıcı "birebir getir" dedi; davranışı oradan port et, kendi uydurma sistemini kurma.
- Ek iş: dinamik yansımalar (ayna + canlı küp harita) — DirectX katmanında, aşağıda.
- Kişisel kullanım, dağıtım yok. Git deposu **yok**; dosyaları dikkatli düzenle, önemli dosyaların yedeğini al.

## Kullanıcı ve dil

- Kullanıcı **Türkçe** yazar; cevaplar **Türkçe** olmalı.
- Kod yorumları ve dosya içi açıklamalar mevcut kod gibi **İngilizce**; çevredeki koda uy.
- Kullanıcı test edip ekran görüntüsü atar; geri bildirimi kısa ve doğrudandır ("titreme var", "alakasız açı").

## Değişmez kurallar

1. **Kullanıcının açık oyununu sormadan kapatma.** Yeniden başlatma gerekiyorsa önce sor (AskUserQuestion).
   `_mod/rebuild.sh` oyun açıksa durur; ancak `kill` argümanıyla kapatır — onu yalnızca izin alınca kullan.
2. Eski mekaniğe geri dönme ya da "yanına ekleme" önerme; değiştirme isteniyor.
3. Görev uyumluluğu korunmalı: öğretici sallanma noktaları yeni sallanmayla tamamlanmalı, çekme/ağ/zip hedefleri
   yeni tuşlarla çalışmalı (aşağıda "Görev uyumluluğu").
4. Bir şeyi "çalışıyor" diye bildirmeden önce oyunda doğrula (kayıt dosyası + ekran görüntüsü). Doğrulayamadıysan söyle.

## Klasör yapısı

| Yol | İçerik |
|---|---|
| `MSMSpidey/Classes/*.uc` | Mod paketi kaynakları (UnrealScript) → `System/MSMSpidey.u` |
| `MSMSpidey/Classes/MSMSpideyController.uc` | Tüm mekanikler: hareket durumları, kamera, sallanma, dövüş, görev köprüsü, yansıma çizimi |
| `MSMSpidey/Classes/MSMSpideyPawn.uc` | `SpideyPawn` alt sınıfı: hasar/saldırı kancaları, mesh dönüşü |
| `MSMSpidey/Classes/MSMHud.uc` | Interaction katmanı: odak çubuğu, kombo, ipuçları, yansıma dokularını tetikleme, F9 görünümü |
| `MSMSpidey/Classes/MSMAnchor.uc` | Görünmez aktör (ip hedefi, ayna kamerası) |
| `_mod/loader/d3d8proxy.cpp` | `System/d3d8.dll` yükleyicisi: appInit kancası, commandlet çalıştırıcı, `-modlog`, kontrolcü sınıfı değiştirme |
| `_mod/loader/msm_reflect.cpp` | Dinamik yansımalar (D3D9 seviyesinde) |
| `_mod/loader/build.cmd` | DLL derleme (MSVC x86) |
| `_mod/third_party/d3d8to9` | d3d8to9 v1.16.0 (BSD) + MSM yamaları (`_mod/third_party/d3d8to9-msm.patch`) |
| `_mod/decomp/<Paket>/*.uc` | Orijinal paketlerin decompile edilmiş kaynakları (yalnızca okuma/başvuru) |
| `_mod/tools/Decomp` | UELib tabanlı decompiler: `Decomp.exe <paket.u> <çıktıKlasörü>` |
| `_mod/tools/*.py` | PE yardımcıları (dis/xref/vtbl; pefile + capstone) |
| `_mod/rebuild.sh` | `MSMSpidey.u`'yu derle, isteğe bağlı oyunu aç |
| `örnekhtml/` | Kullanıcının referans Three.js oyunu (kendi `AGENT.md`'si var) |
| `MODLOG.md` | Teknik günlük: araç zinciri, doğrulanmış gerçekler, durum |

## Derleme ve çalıştırma

- **Script paketi:** `bash _mod/rebuild.sh [kill] [run]` (Git Bash). Oyun kapalı olmalı (`MSMSpidey.u` kilitlenir).
  Arkada `Webhead.exe -ucc=Editor.MakeCommandlet` çalışır; sonuç `System/ModLoader.log`'da, başarı satırı
  `Success: Compiled ...`. `run` oyunu `-modlog` ile açar.
- **Yükleyici DLL:** PowerShell'den `& cmd /c "H:\Spider-Man 2\_mod\loader\build.cmd"` → `_mod/loader/d3d8.dll`.
  Bash'ten `cmd //c` sessizce başarısız olur. Kurulum: oyun kapalıyken `System/d3d8.dll` üzerine kopyala
  (açıkken "Device or resource busy"). Önceki sürümler: `d3d8.prev-native.dll`, `d3d8.prev-cube.dll`.
- **Kayıtlar:** `System/ModLoader.log` (GLog/GWarn, `-modlog` ile; `MSMDBG` saniyede bir, `MSMREFL` yansıma),
  `System/MSMReflections.log` (DLL tarafı istatistik ve matrisler).
- **Yedek:** `<yedek-zip>` (tüm System klasörü).

## Motorla ilgili temel gerçekler

- Script kaynakları `.u` dosyalarından silinmiş (ScriptText " "). Stok sınıfları okumak için `_mod/decomp` kullan.
- MakeCommandlet, kaynağı silinmiş stok sınıfları yeniden derlemeye çalışır; yükleyici Editor.dll'deki CRC
  kontrolünü çalışma anında yamalar (RVA 0x8fb37, jne→nop).
- Menüler `?Game=Webhead.WebheadGameInfo` ile seyahat eder; ini'deki DefaultGame ve ServerActors (standalone) etkisiz.
  Yükleyici WebheadGameInfo varsayılan `PlayerControllerClassName`'ini (ofset 0x484) `MSMSpidey.MSMSpideyController`
  yapar.
- Pawn sınıfı `System/User.ini` `[DefaultPlayer] Class=MSMSpidey.MSMSpideyPawn` ile gelir (Webhead.ini [URL] değil).
- Fare ile bakış: `Webhead.ini [WinDrv.WindowsClient] MouseX/YMultiplier=1` (0 = imleç modu).
- Ölçek: **1 m = 53 uu** (`S`). Motor yerçekimi 1500 telafi edilip etkin 30 m/s². Fizik: havada PHYS_Falling,
  yerde PHYS_Walking, duvar/pointZip PHYS_Flying; karede bir fizik adımı + ip için öngörülü sınırlama.
- `*Startup` haritaları menüdür; MSM orada devreye girmez (`IsMenuLevel`). MSM, Possess'ten sonra tembel başlar.
- Oyun **odak kaybedince duraklar** (duraklatma menüsü açılır).

## Tuş düzeni (User.ini, alias 26–33)

WASD hareket, fare kamera · Shift sallanma/parkur/duvar koşusu · Space zıplama (basılı = şarjlı) / bırakma ·
Sol tık saldırı · Sağ tık ağ atışı (hedef çekme/ağ/ateş/al/kullan ise stok eylem) · Q ağ zip · E nokta fırlatma
(Zip hedefinde stok zip) · C kaçınma/dalış · F bitiriş · R stok bağlam eylemi (`MSMUse`; 'swing' ve 'attack' hariç) ·
F9 yansıma dokuları hata ayıklama görünümü. Ctrl boş.
Space aliası stok `Jump`'ı da gönderir, böylece stok durumlardan (stok sallanma vb.) kaçış mümkün.

## Görev uyumluluğu

- Stok `ThirdPersonCamera` her karede MSM bakışına çevrilip stok `FindTarget()` çağrılır → stok hedef/nişangâh ve
  `Target/FireAction` çalışır (`UpdateContextTarget`). Stok eylemler `DoAction` ile: Pull/Web/Shoot/Pickup/Use/Zip.
- Sallanma noktaları: havada 60 m içindeki `WebSwingPoint` tercih edilir; bağlanınca `SwingTrigger()`, bırakınca
  `ReleaseTrigger()`; `TargetableRadius` içinden sallanarak geçmek de tetikler. Doğrulandı: CB3_CityStreet
  öğretici olayları SwingFire01A..08.
- `PlayerWalking` içinde Fire/AltFire/Jump MSM aktifken etkisiz; stok kaldır/fırlat durumları AltFire kullanır.

## Dinamik yansımalar

Stok oyun her bölgede tek bir sabit küp harita kullanır. Mod iki parçalı canlı yansıma yapar:

- **UnrealScript** (`RenderTexture`): her karede iki ScriptedTexture doldurur:
  `ReflTex` 2048x1024 = kameradan 6 küp yüzü (512, D3D küp düzeni, D3D (X,Y,Z) = UE (Y,Z,X), Spidey gizli);
  `MirrorTex` 2048x2048 = sol üstte ekran x1.06 boyutunda, en yakın duvara göre yansıtılmış kameradan ayna görüntüsü
  (`FindReflPlane`, aktörleri de izleyen 5 ışın; buradaki binalar BSP).
- **Tuzak:** HUD dokuları her kare 1x1 toplamsal pikselle çizer, renk **1/255**. Tamamen siyah çizim canvas
  tarafından atlanır ve dokular **hiç yenilenmez**.
- **DLL** (`msm_reflect.cpp`, d3d8to9 üstünde): her çizimde render hedefini kontrol eder, hedef başına görüş
  matrislerini toplar, ayna düzlemini ana/ayna kameralarının orta düzlemi olarak bulur, ayna çizimini duvarın
  arkasında kırpar ve her yansıtıcı çizimi clip plane'lerle 3 geçişe böler: düzlem üstü (±48 uu) → ayna dokusu
  (ayna kamerasının view*proj'u ile projeksiyon), geri kalan → canlı küp (kendi doku matrisiyle).
- UE2 portal için D3D viewport ayarlamaz; ayna dikdörtgeni arka tampon boyutundan yeniden hesaplanır.
- d3d8to9'da fonksiyonsuz D3D8 "vertex shader" = sabit fonksiyon (`ShaderInfo->Shader == nullptr`).
  `d3d8to9_base.cpp` CreateDevice `D3DCREATE_PUREDEVICE`'ı kaldırır (durum geri okunuyor).
- Ayarlar `System/MSMReflections.ini` `[MSMReflections]`: `Enabled`, `Planar`; test anahtarları (120 karede bir
  okunur, yeniden başlatma gerekmez): `Mips`, `Override`, `Debug` (1 = ayna yüzeylerinde ham ayna görüntüsü,
  2 = her yerde ham küp). Test bitince `Debug`'ı kaldır.

## Oyunu kendin sürmek (test)

- `um win shot --exe Webhead.exe out.png` (GPU güvenli ekran görüntüsü), `um win drive --proc Webhead "focus" ...`
  (`key 0x1B`, `hold 0x57 1200`, `rel dx dy`, `sleep ms`).
- Senin araç çağrıların odağı oyundan alır → oyun duraklar. Her görüntüden önce `focus` + `key 0x1B` (devam) gönder,
  görüntüyü odak oyundayken al (sürüşü arka planda çalıştırıp birkaç saniye içinde çek).
- Oyun açılışı: ~12 sn bekle, giriş videoları ve bölüm başı ara sahnesi için birkaç kez Esc, sonra Enter.

## Bilinen açıklar / yapılacaklar

- Doğrulanmadı: haydutlara karşı dövüş, stok çekme/ağ/zip görevleri, stok durumlardan Space ile kaçış.
- Ayna aynı anda tek (en yakın) düz duvar için; diğer yüzeyler küp haritayla.
- Kararlı olunca `bMSMDebug` kaydını kapat; `MSMReflections.log`'daki periyodik iz satırları da kaldırılabilir.
- Her değişiklikten sonra `MODLOG.md`'ye kısa ve doğrulanmış bilgi ekle.
