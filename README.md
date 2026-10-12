# Spider-Man 2 (2004, PC) — Marvel's Spider-Man mekanikleri modu

Unreal Engine 2 tabanlı **Spider-Man 2 (2004)** oyununun hareket, kamera, ağla sallanma, dövüş ve ayarlar
sistemini **Marvel's Spider-Man (Insomniac)** tarzına getiren, kişisel kullanım amaçlı deneysel bir mod.
Bu depo yalnızca **kaynak kodu ve araçları** içerir. Oyun dosyaları, çıkarılmış modeller/dokular, derlenmiş
paketler ve üçüncü taraf varlıklar **yoktur** ve eklenmemelidir (`.gitignore` bunları dışlar).

> Resmî olmayan bir hayran çalışmasıdır. Spider-Man 2 ve Marvel's Spider-Man ilgili hak sahiplerine aittir.
> Çalıştırmak için kendi (yasal) oyun kopyanız gerekir.

## İçerik

| Klasör | Ne var |
|---|---|
| `MSMSpidey/Classes` | UnrealScript mod paketi (`MSMSpidey.u`): hareket durumları, kamera, sallanma, dövüş, HUD, Türkçe ayar ekranı |
| `loader/` | `d3d8.dll` yükleyici (d3d8to9 tabanlı): dinamik yansımalar (ayna + küp harita), grafik ayarları, `-ucc=` komut satırı çalıştırıcı, `-msmexec=` editör betiği çalıştırıcı (PSK/doku içe aktarma) |
| `third_party/d3d8to9-msm.patch` | [crosire/d3d8to9](https://github.com/crosire/d3d8to9) (BSD-2) için yama; kaynağı kendiniz indirin |
| `pylib/`, `suit_port/` | Insomniac `.suit` → UE2 `.ukx` dönüştürme araçları (retarget, doku DXT1, PSK yazıcı). **Girdi dosyaları dahil değildir** |
| `optional/` | Raimi kostümü için pawn sınıfı (kendi `MSMSuit.ukx`'inizi üretmeniz gerekir) |
| `tools/`, `docs/` | derleme/yardımcı betikler; `AGENT.md` (proje rehberi), `MODLOG.md` (doğrulanmış teknik günlük) |

## Derleme (özet)

1. **Yükleyici DLL** (x86, MSVC): `crosire/d3d8to9` kaynağını `third_party/d3d8to9` altına koyup
   `d3d8to9-msm.patch`'i uygulayın, sonra `loader/build.cmd`. Çıktıyı oyunun `System/d3d8.dll` olarak kurun.
2. **UnrealScript**: `MSMSpidey/Classes` klasörünü oyun dizinine koyup `Webhead.exe -ucc=Editor.MakeCommandlet`
   (yükleyici bunu sağlar) → `System/MSMSpidey.u`. `tools/build_offline.sh` oyun açıkken ayrı bir kopyada derler.
3. `Webhead.ini`: `[Engine.Engine] GUIController=MSMSpidey.MSMGUIController`, `[URL] Class=MSMSpidey.MSMSpideyPawn`.

Ayrıntılar ve tuzaklar için `docs/AGENT.md` ve `docs/MODLOG.md`.

## Raimi kostümü (denemelik, çalışmıyor)

`suit_port/` ile Marvel's Spider-Man Remastered "Raimi 2007" `.suit` dosyası 231 kemikli iskeletten oyunun 77
kemikli iskeletine yeniden hedeflenip (`retarget.py`) PSK → `.ukx` olarak içe aktarılabiliyor; geometri, doku
ve skin ağırlıkları oyunda doğru görünüyor. **Bilinen sorun:** içe aktarılan mesh'te oyunun animasyonları
uygulanmıyor (T-poz). Kök neden bulunamadı; bulguların listesi `docs/MODLOG.md` / `suit_port/RESEARCH.md`'de.

## Lisans

Kod: MIT (aşağıdaki `LICENSE`). Üçüncü taraf kod/varlıklar kendi lisanslarına tabidir.
