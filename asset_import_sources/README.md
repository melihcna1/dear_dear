# Asset Import Sources

Bu klasör Asset Importer'ın proje içindeki ham GLB kaynak kitaplığıdır. `.gdignore`
dosyasını silmeyin; bu sayede Godot bu ham kaynakları oyun asset'i olarak ayrıca
import etmez. Importer, seçilen kaynaklardan standart dosyaları `assets/dev_model/`
altında üretir.

Kaynak kitaplığı 30 Ağustos 2026 tarihinde şu klasörden hazırlanmıştır:

`C:\Users\pc\Downloads\__Dev Model-20260828T112155Z-1-001\__Dev Model`

- 305 benzersiz ve desteklenen GLB yapılandırıldı.
- `_Arşiv (burayı alma)` dahil edilmedi.
- FBX, GLTF/BIN, PNG ve uzantısız animasyon dosyaları dahil edilmedi.
- `310174`, `310176` ve `310177` için bulunan birebir `(1)` kopyaları atlandı.
- Aşağıdaki yedi model kategori bilgileri belirsiz olduğu için otomatik olarak
  eklenmedi; mevcut importer bunları yanlışlıkla `Furniture / Decor` sayardı:
  - `character/dear_dear_female_rig_character.glb`
  - `character/dear_dear_male_rig_character.glb`
  - `map/Ev 1/interior_house_1.glb`
  - `map/Karakter Yapma Ekranı/interior_characterscreen.glb`
  - `map/Karakter Yapma Ekranı/prop_character_withwings.glb`
  - `hamsi, olta, paket/hamsi.glb`
  - `hamsi, olta, paket/giftpack/prop_giftpack.glb`

## Kullanım

1. Godot'ta **Asset Importer** sekmesini açın.
2. **Add GLB Files to Project** düğmesine basın.
3. Bu klasörde `cloth/` veya `furniture/` altına gidip GLB seçin.
4. Eski dosya adındaki ID'yi elle kullanmayın; bazı eski ID'ler çakışıyor.
   **Auto ID** açık kalsın.
5. Kategori ve metadata'yı kontrol edip capture/export/sync adımlarını uygulayın.

Bir kayıt kuyruğa alındıktan sonra ilgili ham GLB'yi taşımayın veya silmeyin.
