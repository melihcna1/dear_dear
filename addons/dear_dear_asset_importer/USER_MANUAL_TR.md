# Asset Importer Kullanım Kılavuzu

Bu kılavuz; kendi içinde eksiksiz GLB modellerinin içe aktarılmasını, standart pazar görsellerinin oluşturulmasını, yönetilen varlık kataloğunun güncellenmesini ve kayıtların Google E-Tablolar ile eşitlenmesini açıklar.

Asset Importer bir Godot editör aracıdır. Projenin oynanabilir ana sahnesini değiştirmez.

> **Not:** Godot içindeki düğme ve alan adları, ekranda kolayca bulunabilmeleri için kılavuzda İngilizce halleriyle yazılmıştır.

## 1. İçe aktarıcının oluşturduğu dosyalar

İçe aktarıcı, tamamlanan her varlık için şunları oluşturabilir:

- Kaynak `.glb` dosyasının, yapılandırılmış proje klasöründeki standartlaştırılmış bir kopyası.
- Oluşturulan sprite adına sahip, şeffaf arka planlı 1024×1024 pazar görseli.
- `data/asset_catalog.json` içinde bir kayıt.
- `data/asset_exports/asset_catalog.csv` içinde aynı kayda karşılık gelen bir satır.
- Ekibin Google E-Tablosunda eşitlenmiş bir satır.

Orijinal GLB dosyası, bulunduğu konumda değiştirilmeden kalır.

## 2. Gereksinimler

Başlamadan önce şunları kontrol edin:

- Proje Godot 4.6 ile açık olmalıdır.
- Ana editör araç çubuğunda **Asset Importer** sekmesi görünmelidir.
- Her kaynak dosya, ikili biçimde ve kendi içinde eksiksiz bir `.glb` dosyası olmalıdır.
- Kaynak GLB; harici doku, tampon veya başka dosyalara bağımlı olmamalıdır.
- Proje dosyalarına nihai kayıt yapılacaksa Google E-Tablolar bağlantısı yapılandırılmış olmalıdır.

Google E-Tablolar bağlantısı olmadan önizleme ve **Temporary Capture Test** kullanılabilir. Nihai GLB ve PNG kayıtları için sunucu üzerinde başarılı bir kimlik rezervasyonu gerekir.

## 3. Google E-Tablolar için ilk kurulum

Bu bölümün normalde proje sahibi veya teknik sorumlu tarafından yalnızca bir kez uygulanması gerekir.

1. Ekibin kullanacağı Google E-Tablosunu oluşturun veya mevcut tabloyu seçin.5070253058
2. E-Tabloda **Uzantılar → Apps Script** menüsünü açın.
3. Apps Script editöründeki içeriği `addons/dear_dear_asset_importer/google_apps_script/Code.gs` dosyasının içeriğiyle değiştirin ve kaydedin.
4. Apps Script içinde **Proje Ayarları → Komut dosyası özellikleri** bölümünü açın ve şunları ekleyin:
   - `SHARED_SECRET`: Yalnızca aracı kullanan kişilerce bilinen, uzun ve rastgele bir gizli değer.
   - `SPREADSHEET_ID`: E-Tablo adresindeki `/d/` ile `/edit` arasında bulunan değer.
   - `SHEET_NAME`: İsteğe bağlıdır; varsayılan değer `Asset Catalog` olur.
5. `runDearDearAssetImporterSelfTests` fonksiyonunu bir kez çalıştırın ve istenen izinleri onaylayın.
6. **Dağıt → Yeni dağıtım → Web uygulaması** seçeneğini açın.
7. Web uygulamasını komut dosyası sahibi olarak çalışacak ve bağlantıya sahip herkes erişebilecek şekilde ayarlayın.
8. Sonu `/exec` ile biten dağıtım adresini kopyalayın.
9. Godot içinde **Asset Importer → Sheets Settings** penceresini açın.token
10. `/exec` adresini ve aynı gizli değeri girip **Save** düğmesine basın.
11. **Refresh IDs** düğmesine basın. Araç çubuğunda **Sheets: connected** yazmalıdır.

Adres ve gizli değer proje dosyalarına değil, mevcut kullanıcının Godot editör ayarlarına kaydedilir. Bunların yerine aşağıdaki ortam değişkenleri de kullanılabilir:

- `DEAR_DEAR_ASSET_WEBHOOK_URL`
- `DEAR_DEAR_ASSET_SHARED_TOKEN`

Ortam değişkenleri tanımlıysa **Sheets Settings** penceresine girilen değerlerden öncelikli olur.

## 4. Arayüzün genel görünümü

Godot'un 2D, 3D, Script, Game ve AssetLib sekmelerinin yanında bulunan **Asset Importer** sekmesini açın.

Çalışma alanı şu ana bölümlerden oluşur:

- **3D Viewport & Capture Studio:** Seçili modeli önizler ve pazar görselinin kadrajını ayarlamanızı sağlar.
- **Selection, Settings & Info:** Etkin kuyruk dosyasının meta verilerini düzenler; oluşturulan dosya adlarını ve durumunu gösterir.
- **File List & Output Actions:** İçe aktarma kuyruğunu ve yakalama, dışa aktarma, eşitleme işlemlerini içerir.
- **Üst araç çubuğu:** Yerel ve uzaktaki kimlikleri yeniler, E-Tablo ayarlarını açar, bağlantı durumunu ve yerel kimlik çakışmalarını gösterir, işlem mesajlarını bildirir.

## 5. Standart içe aktarma iş akışı

### Adım 1: Kimlikleri yenileyin

Nihai içe aktarma oturumuna başlamadan önce **Refresh IDs** düğmesine basın.

Bu işlem proje varlıklarını yeniden tarar, Google E-Tablolar üzerindeki kalıcı olarak alınmış kimlikleri yeniler ve **Last** ile **Next available** göstergelerini günceller. E-Tabloya erişilemiyorsa meta verileri hazırlamaya ve deneme çekimi yapmaya devam edebilirsiniz; ancak kimliğe bağlı nihai kayıt işlemlerini yapamazsınız.

### Adım 2: GLB dosyalarını ekleyin

1. **Add GLB Files to Project…** düğmesine basın.
2. Erişilebilir herhangi bir klasörden bir veya birden fazla `.glb` dosyası seçin.
3. Düzenlemek ve önizlemek istediğiniz kuyruk satırını seçin.

Her satır bağımsız bir taslaktır. Bir satırın öğe adını, kimliğini veya meta verilerini değiştirmek diğer satırları etkilemez.

Seçilen GLB dosyaları projenin içindeki `asset_import_sources/` ham kaynak kutusuna kopyalanır. Böylece proje ZIP'lendiğinde kaynaklar da gider; klasördeki `.gdignore` işareti ise Godot'un bu ham dosyaları oyun varlığı olarak içe aktarmasını ve yönetilen çıktı çakışması saymasını engeller. **Open Source Folder** klasörü açar. Kuyruktaki kaynak silindiyse veya kaydı güncel bir GLB ile değiştirmek istiyorsanız **Relink / Replace Source…** kullanın.

İçe aktarıcı, okunamayan dosyaları ve harici bağımlılıklar içeren GLB dosyalarını reddeder. Böyle bir modeli tekrar denemeden önce kendi içinde eksiksiz bir GLB olarak dışa aktarın veya yeniden paketleyin.

### Adım 3: Meta verileri girin

Kuyruktaki her dosya için **Selection, Settings & Info** bölümündeki alanları doldurun:

| Alan | Kullanımı |
|---|---|
| **Main category** | Varlığın ana kategorisini seçin. Kimlik aralığını, adlandırma önekini, cinsiyet kuralını ve hedef klasörü belirler. |
| **Subcategory** | Yapılandırılmış türler arasından en uygun alt kategoriyi seçin. Kaydedilecek kamera profilini de belirler. |
| **Gender** | Yalnızca giyim gibi cinsiyet kullanan kategorilerde zorunludur. Female, Male veya Unisex seçin. |
| **Item name** | `Summer Sweater` gibi okunabilir bir ad girin. Araç bunu küçük harfli, dosya adına uygun bir ifadeye dönüştürür. |
| **Item ID** | Normal kullanımda **Auto** seçili kalsın. Yalnızca belirli ve geçerli altı haneli bir kimlik atanmışsa **Auto** seçimini kapatın. |
| **Buyable** | Öğe satın alınabiliyorsa etkinleştirin. |
| **Sellable** | Öğe satılabiliyorsa etkinleştirin. |
| **ID in filename** | Oluşturulan dosya adına kimliği ekler. Clothes ve Furniture için zorunludur. Yalnızca isteğe bağlı olarak yapılandırılmış kategorilerde kapatılabilir. Kimlik, dosya adından çıkarılsa bile veritabanı kaydında tutulur. |
| **Confirm update…** | Yalnızca aynı katalog kaydına ait mevcut dosyaları bilinçli olarak değiştireceğiniz zaman etkinleştirin. Başka bir kaydın dosyalarının üzerine yazılmasına izin vermez. |

Salt okunur **Asset filename** ve **Sprite name** alanlarını kontrol edin. Kaydı düzenledikçe bu adlar otomatik güncellenir.

Aynı sınıflandırmayı kullanan bir toplu işlem için:

1. Etkin satırda ortak kategori ayarlarını tamamlayın.
2. Dosya listesinde uygulanacak satırları çoklu seçin.
3. **Apply Category Settings to Selected** düğmesine basın.

Bu işlem; kategori, alt kategori, cinsiyet, satın alınabilir/satılabilir işaretleri ve dosya adında kimlik politikasını kopyalar. Dosyaya özel öğe adları, kimlikler, yollar, oluşturulan adlar, doğrulama sonuçları ve durumlar bağımsız kalır.

### Adım 4: Önizleme kadrajını ayarlayın

Seçili modeli kadraja almak için şu kontrolleri kullanın:

- **Sol tuşla sürükleme:** Modelin etrafında dönme.
- **Shift + sol tuşla sürükleme:** Kaydırma.
- **Orta tuşla sürükleme:** Kaydırma.
- **Fare tekerleği:** Yakınlaştırma ve uzaklaştırma.

İçe aktarıcı, tutarlı kadraj sağlamak için model sınırlarını normalize eder. Kamera açıları ana kategori ve alt kategoriye göre kaydedilir; böylece benzer varlıklar aynı sunum açısını kullanabilir. Dosyalar arasında geçiş yapmak profili sıfırlamaz.

Yalnızca etkin kategori/alt kategori profilini varsayılan ayarına döndürmek istediğinizde **Reset Camera Angle** düğmesine basın. Diğer profiller etkilenmez.

Ortam, ana, dolgu ve arka ışık şiddetlerini ayarlamak için **Lighting Settings** düğmesini kullanın. Değerleri hem canlı önizlemeye hem de nihai PNG çekimine uygulamak için **Apply**, standart stüdyo düzenine dönmek için **Reset Defaults** düğmesine basın. Aydınlatma ayarları içe aktarıcı günlüğünde kullanıcıya özel saklanır.

Dosyalara zarar vermeyen bir kontrol için **Temporary Capture Test** düğmesini kullanın. Araç, kimlik rezerve etmeden ve proje varlıklarını yazmadan Godot kullanıcı verisi klasörüne bir deneme görseli kaydeder.

### Adım 5: Taslağı doğrulayın

Yakalama işleminden önce şunları kontrol edin:

- Doğru model görünmelidir.
- Ana kategori ve alt kategori doğru olmalıdır.
- Gerekliyse cinsiyet seçilmiş olmalıdır.
- Öğe adı anlaşılır ve doğru yazılmış olmalıdır.
- Oluşturulan dosya adları doğru olmalıdır.
- **Sheets: connected** görünmelidir.
- Etkin kayıt için hata mesajı bulunmamalıdır.

Temiz bir projede yerel denetim model çakışması bildirmemelidir. Ham eski modelleri **Add GLB Files to Project…** veya **Open Source Folder** aracılığıyla `asset_import_sources/` içinde tutun; kimlik içeren dosya adlarını doğrudan `res://assets` altına koymak bu kimlikleri yeniden yerel sahip olarak işaretler.

### Adım 6: Görseli yakalayın ve kaydedin

1. Kuyrukta hazır olan bir veya daha fazla satırı seçin.
2. **Capture & Save Market PNG Image** düğmesine basın.

İçe aktarıcı, seçili her kayıt için sırayla şunları yapar:

1. Meta verileri ve hedef yolları doğrular.
2. Google E-Tablolar üzerinde kalıcı, altı haneli bir kimliği atomik biçimde rezerve eder.
3. Kaynak GLB'yi yapılandırılmış proje kategori klasörüne kopyalar.
4. Şeffaf arka planlı 1024×1024 PNG dosyasını oluşturup kaydeder.
5. Kaydı **Captured** durumuna geçirir.

İçe aktarma daha sonra terk edilse bile kimlik rezervasyonu kalıcıdır. Kimlikler bilinçli olarak yeniden kullanılmaz. Aynı taslak yeniden denendiğinde yeni bir kimlik oluşturmak yerine mevcut `record_id` ve rezervasyon kullanılır.

### Adım 7: Yönetilen kataloğu dışa aktarın

Yakalamadan sonra ilgili satırları seçip **Export CSV / JSON** düğmesine basın.

Bu işlem her kaydı atomik olarak şu dosyalara ekler veya günceller:

- `data/asset_catalog.json`
- `data/asset_exports/asset_catalog.csv`

CSV dosyası, yönetilen JSON kataloğundan her zaman aynı sırada ve belirli biçimde yeniden oluşturulur. Başarıyla yazılan kayıt **Exported** durumuna geçer.

### Adım 8: Google E-Tablolar ile eşitleyin

Dışa aktarılmış satırları seçip **Sync Google Sheets** düğmesine basın.

Bu işlem uzaktaki satırları tamamlar veya günceller, E-Tablo durumunu `ready` olarak değiştirir ve her yerel taslağı **Synced** durumuna geçirir. Eşitleme sabit `record_id` ile yapıldığı için aynı işlemi tekrar çalıştırmak güvenlidir.

### Adım 9: Sonucu doğrulayın

Önemli varlıklarda şunları doğrulayın:

- Standartlaştırılmış GLB, gösterilen proje hedefinde bulunmalıdır.
- PNG 1024×1024 boyutunda, şeffaf, doğru kadrajlanmış ve boş olmayan bir görsel olmalıdır.
- JSON ve CSV satırları doğru meta verileri ve yolları içermelidir.
- Google E-Tabloda aynı kayıt ve öğe kimliğine sahip tek bir `ready` satırı bulunmalıdır.

## 6. Durumların anlamları

| Durum | Anlamı | Normal sonraki işlem |
|---|---|---|
| **Draft** | Dosya ve meta veriler hazırlanmaktadır. Henüz kalıcı bir kimlik garanti edilmez. | Doğrulamayı tamamlayıp yakalama işlemini başlatın. |
| **Reserved** | Google E-Tablolar kayda kalıcı bir kimlik atamış, fakat yerel yakalama tamamlanmamıştır. | **Capture & Save Market PNG Image** işlemini yeniden deneyin. |
| **Captured** | Standartlaştırılmış GLB ve PNG yazılmıştır. | **Export CSV / JSON** işlemini çalıştırın. |
| **Exported** | Yönetilen yerel JSON ve CSV katalogları kaydı içerir. | **Sync Google Sheets** işlemini çalıştırın. |
| **Synced** | Yerel çıktılar ve uzaktaki `ready` satırı tamamlanmıştır. | Sonucu doğrulayın; başka işlem gerekmez. |
| **Error** | Son işlem başarısız olmuş veya doğrulama bir sorun bulmuştur. | Görüntülenen mesajı okuyun, nedeni düzeltin ve uygun işlemi tekrar deneyin. |

Taslaklar, işlem ilerlemesi, kamera profilleri ve proje içi kaynak yolları `.godot/dear_dear_asset_importer/` altında saklanır. Eski bir taslak hâlâ erişilebilen harici bir dosyayı gösteriyorsa proje yeniden açıldığında dosya otomatik olarak `asset_import_sources/` içine kopyalanır ve günlük yolu güncellenir.

## 7. Adlandırma kuralları

Öğe adları küçük harfli snake_case biçimine dönüştürülür. `_Rig` gibi yalnızca kaynakta anlam taşıyan son ekler, yeni standart adlardan kaldırılır.

Giyim varlıkları şu kalıbı kullanır:

```text
<cinsiyet_kodu>_cloth_<alt_kategori>_<öğe_kısa_adı>_<kimlik>.glb
```

Örnek:

```text
f_cloth_top_summer_sweater_310149.glb
f_cloth_top_summer_sweater_310149_s.png
```

Diğer kategoriler şu kalıbı kullanır:

```text
<kategori_öneki>_<alt_kategori_öneki>_<öğe_kısa_adı>_<kimlik>.glb
```

Pazar görseli her zaman oluşturulan sprite adını kullanır. Sprite adı, varlık adının sonuna `_s` eklenerek oluşturulur.

Cinsiyet kodları:

- Female: `f`
- Male: `m`
- Unisex: `u`

## 8. Kimlik aralıkları

Kimlikler altı haneli metin değerleridir. Yalnızca yapılandırılmış aralıklar kullanılabilir; belirtilmemiş ve rezerve edilmiş bloklar reddedilir.

| Kategori | Kullanılabilir kimlikler |
|---|---:|
| Seeds | 110000–119999 |
| Crops | 120000–129999 |
| Food | 130000–139999 |
| Furniture | 210000–299999 |
| Cloth | 310000–399999 |
| Beauty | 410000–419999 |
| Utility | 420000–429999 |
| Chat / Effects | 430000–439999 |
| Recipe / Craft | 610000–699999 |
| Market / Shop | 710000–999999 |

Otomatik atama, ilgili aralıkta kalıcı olarak alınmış en yüksek kimliği bulur ve sonraki geçerli değeri kullanır. Yerel varlıklar, yönetilen katalog, kuyruktaki kayıtlar ve Google E-Tablolar denetlenir. Aradaki boşluklar yeniden kullanılmaz.

Manuel kimliği yalnızca ekip tarafından belirlenmiş özel bir gereksinim varsa kullanın. Manuel kimlik:

- Tam olarak altı rakam içermelidir.
- Seçili kategorinin izin verilen aralığında olmalıdır.
- Rezerve edilmiş bir blokta olmamalıdır.
- Farklı bir yerel varlık, katalog kaydı, kuyruk taslağı veya E-Tablo satırı tarafından kullanılmamalıdır.

## 9. Bir kaydı güncelleme veya yeniden yakalama

Bu işlemi yalnızca mevcut çıktı aynı yönetilen kayda aitse uygulayın:

1. Orijinal taslağı/kaydı geri yükleyin veya seçin.
2. `record_id`, öğe kimliği ve hedeflerin doğru olduğunu kontrol edin.
3. **Confirm update of this record's existing output files** seçeneğini etkinleştirin.
4. Gerekiyorsa meta verileri veya kamera kadrajını değiştirin.
5. **Capture & Save Market PNG Image** işlemini tekrar çalıştırın.
6. **Export CSV / JSON** işlemini çalıştırın.
7. **Sync Google Sheets** işlemini çalıştırın.

İçe aktarıcı, başka bir kayda ait hedefi engeller. Yönetilen dosyaları elle silerek veya yeniden adlandırarak bu korumayı aşmayın; çakışan meta veriyi ya da hedefi düzeltin.

## 10. Bir taslağı kaldırma

Çalışma kuyruğunda artık görünmemesi gereken taslağı seçip **Remove Draft** düğmesine basın.

Bir taslağın kaldırılması, daha önce rezerve edilmiş kimliği yeniden kullanılabilir hâle getirmez. Tamamlanmış proje varlıklarını, katalog kayıtlarını veya E-Tablo satırlarını da otomatik olarak silmez.

## 11. Sorun giderme

### Asset Importer sekmesi görünmüyor

**Project → Project Settings → Plugins** bölümünü açıp Dear Dear Asset Importer eklentisinin etkin olduğunu doğrulayın. Yeni etkinleştirildiyse gerekirse editör çalışma alanını yeniden açın.

### Sheets: not configured

**Sheets Settings** penceresini açın, Apps Script `/exec` adresini ve ortak gizli değeri girin, kaydedin ve **Refresh IDs** düğmesine basın. Ortam değişkenleri tanımlıysa editör alanlarındaki değerleri geçersiz kıldıklarını unutmayın.

### Sheets yapılandırılmış fakat bağlanmıyor

İşlem mesajını okuyup şunları doğrulayın:

- Adres, Apps Script editör adresi değil, dağıtılmış `/exec` adresi olmalıdır.
- Ortak gizli değer `SHARED_SECRET` ile tamamen aynı olmalıdır.
- Dağıtım etkin ve erişilebilir olmalıdır.
- `SPREADSHEET_ID` doğru E-Tabloyu göstermelidir.
- Bilgisayar `script.google.com` adresine ulaşabilmelidir.

Sorunu düzelttikten sonra **Refresh IDs** düğmesine tekrar basın.

### Çevrimdışıyken nihai yakalama engelleniyor

Bu beklenen davranıştır. Sunucu olmadan benzersiz ve kalıcı kimlik garanti edilemediği için nihai kayıt engellenir. Düzenlemeye ve **Temporary Capture Test** kullanmaya devam edin; nihai yakalamadan önce bağlantıyı geri getirip kimlikleri yenileyin.

### GLB yüklenmiyor

Dosyanın:

- `.glb` uzantısına sahip olduğunu,
- Okunabilir ve bozulmamış olduğunu,
- Tamponlarını ve dokularını kendi içinde barındırdığını,
- Normal bir Godot 3D sahnesinde veya başka bir glTF görüntüleyicide açılabildiğini

kontrol edin. Gerekirse modeli kendi içinde eksiksiz ikili glTF/GLB olarak yeniden dışa aktarın.

### Godot `Task 'reimport' already exists` hatası veriyor

İçe aktarıcı, yakalamadan sonra artık ikinci bir dosya sistemi taramasını zorla başlatmaz. Mesaj eski bir eklenti örneğinden geldiyse eklentiyi kapatıp yeniden etkinleştirin veya tekrar denemeden önce Godot'u yeniden başlatın. FileSystem panelinin oluşturulan GLB, çıkarılan dokular ve PNG içe aktarmasını bitirmesini bekleyin.

### Başka bir kuyruk satırı seçildiğinde eski önizleme kalıyor

Güncel kuyruk seçim davranışını yüklemek için eklentiyi veya Godot'u yeniden başlatın. Çoklu seçim modunda son tıkladığınız satır etkin önizleme olur; seçili satırlar çıktı işlemlerinin hangi kayıtları işleyeceğini belirlemeye devam eder.

### Kimlik reddediliyor

Kimlik kategori aralığının dışında, rezerve edilmiş bir blokta, daha önce alınmış veya mevcut kuyrukta yinelenmiş olabilir. Manuel kimlik gerçek bir boşluğu doldurabilir; ancak E-Tabloda boş görünen bir kimlik mevcut bir yerel GLB/FBX dosya adı veya katalog kaydı tarafından kullanılıyor olabilir. Yerel çakışma mesajı artık bu sahibi gösterir. **Refresh IDs** düğmesine basın, bildirilen yolu/kaydı inceleyin, kategoriyi doğrulayın ve normalde **Auto** atamaya geri dönün.

### Mevcut hedef nedeniyle işlem engelleniyor

Dosyalar aynı kayda aitse açık güncelleme onayını etkinleştirin. Başka bir kayda aitse çakışan öğe meta verisini değiştirin veya sahiplik uyuşmazlığını araştırın. İçe aktarıcı, kayıtlar arasında dosya üzerine yazılmasına izin vermez.

### İşlem kimlik rezervasyonundan sonra durdu

Taslağı koruyun ve **Capture & Save Market PNG Image** işlemini yeniden deneyin. Günlük ve sabit kayıt kimliği sayesinde işlem aynı rezerve edilmiş kimlikle devam eder.

### Birden fazla varlığın çekim kadrajı yanlış

Kamera profili kategori/alt kategori tarafından paylaşılır. Temsilî bir modelle profili ayarlayın veya etkin profil için **Reset Camera Angle** düğmesine basıp kadrajı yeniden oluşturun. Diğer kategori/alt kategori profilleri değişmez.

### Yerel denetim beklenmeyen bir kimlik çakışması bildiriyor

Kimlik içeren bir GLB/FBX doğrudan `res://assets` altına konmuş, iki kuyruk kaydı aynı kimliği kullanıyor veya yönetilen bir çıktı bu kimliğin sahibi olabilir. Tam sahibi görmek için denetim ipucunu ya da yakalama hata mesajını okuyun. Ham GLB'leri **Add GLB Files to Project…** ile ekleyin; araç bunları oyun çıktılarıyla karışmayan `asset_import_sources/` kutusunda tutar.

## 12. Yapılandırma ve bakım

Taksonomi, kategori önekleri, kimlik aralıkları, cinsiyet gereksinimleri, dosya adında isteğe bağlı kimlik davranışı ve çıktı klasörleri şu dosyada tutulur:

```text
data/asset_import_categories.json
```

Proje sorumluları, içe aktarıcı kodunu değiştirmeden bu dosyada alt kategori ekleyebilir veya mevcut kategorileri ayarlayabilir. Bu ayarlar adlandırmayı, doğrulamayı, hedefleri ve gelecekteki kimlik atamalarını etkilediği için değişiklikleri normal kaynak kontrolü incelemesiyle yapın.

Yapılandırma değiştiğinde mevcut varlıklar otomatik olarak taşınmaz, yeniden adlandırılmaz veya geriye dönük doldurulmaz.

## 13. Hızlı kullanıcı kontrol listesi

1. **Asset Importer** sekmesini açın.
2. **Refresh IDs** düğmesine basıp **Sheets: connected** durumunu doğrulayın.
3. Bir veya daha fazla kendi içinde eksiksiz GLB ekleyin.
4. Her satırın meta verilerini doldurup kontrol edin.
5. Önizleme kadrajını ayarlayın ve isterseniz **Temporary Capture Test** çalıştırın.
6. Hazır satırları seçip **Capture & Save Market PNG Image** düğmesine basın.
7. Yakalanmış satırları seçip **Export CSV / JSON** düğmesine basın.
8. Dışa aktarılmış satırları seçip **Sync Google Sheets** düğmesine basın.
9. Satırların **Synced** durumuna geçtiğini ve önemli çıktıların doğru olduğunu doğrulayın.
