# Silahlar

Her silah kendi klasorunde ve kendi sahnesinde yasar: `res://weapons/<ad>/<ad>.tscn`.

## Mimari: silahi el takip eder (el = master)

Silah sahnesi karakterin EL SOKETINE instance edilir:

```
Player/IK_character/RightHandAttach   (BoneAttachment3D -> mixamorig_RightHand)
  Weapon                              (silah sahnesinin koku)
```

`RightHandAttach` gercek el kemigine bagli oldugu icin silah el nereye giderse
oraya gider. Parmak hedefleri de el uzayinda kaldigi icin "hedeflar sabit kaldi,
parmaklar koptu" bozulmasi yapisal olarak imkansizdir: kol/bilek IK'si silahi
tutmaya calismaz, sadece eli hedefe goturur. Soket bulunamazsa (el soketi
olmayan sahneler) eski davranis olan `Player/CameraPivot` kullanilir.

## Sahne duzeni (g18.tscn sablon)

```
Weapon                   (Node3D)  weapon_controller.gd + metadata/weapon_id
  WristPivot             (Node3D)  bilek ekseni (player_controller artik yazmaz)
    RecoilPivot          (Node3D)  geri tepme -- weapon_controller dondurur
      GunVisual          (Node3D)  silah modeli (glb instance)
      GripRight          (Node3D)  sag el tutus noktasi -> parmaklar etrafina sarilir
      GripLeft           (Node3D)  sol el destek noktasi (yonu de onemli)
      FingersRight/      (Node3D)  OPSIYONEL: parmak ucu markerlari
        Thumb|Index|Middle|Ring|Pinky
      FingersLeft/       (Node3D)  OPSIYONEL (sol el)
      Muzzle / EjectPort (Node3D)
```

## Kalibrasyon (silah basina -- sadece bu sahne)

- **Weapon kok transformu**: tutusun EL CERCEVESINDEKI yeri ve yonu. Silahin
  elde nasil durdugunu bu belirler; baska dosyaya dokunmadan ayarlanir.
- **GripRight**: sag elin tutus merkezi. `hand_rig.grip_wrap` acikken parmaklar
  bu noktanin etrafina sarilir (`grip_wrap_radius`, `grip_wrap_reach`).
- **GripLeft**: sol elin konumu VE yonu (donus de kullanilir). Iki elle tutusta
  sol avuc silaha bakar, parmaklar ileri.
- **FingersRight/Left/<parmak>**: verilirse parmak uclari birebir bu markerlara
  gider. Hassas kalibrasyon isteyen silahlarda kullan.
- **left_hand_offset**: silah isterse `weapon_controller.left_hand_offset` ile
  sol eli GripLeft'e gore ek olarak kaydirir/dondurur.

## Parmak kalibrasyonu (marker'lar = otorite)

Parmak ucu hedefi su sirayla cozulur (`hand_rig._finger_target_local`):

1. silahin `Fingers<Side>/<parmak>` marker'i (varsa)
2. `grip_wrap` ACIKken: tutus geometrisinden prosedurel kavrama
3. sahne el marker'i (`RightHandAttach/r_<parmak>_target`)
4. kalan yol: kavrama yoksa parmak duser

Varsayilan `grip_wrap = false`: **sahnede duran el marker'lari otoritedir**.
Editor'de marker'i surukle -> parmak aninda takip eder (hem editor hem oyun).
`ik_character.tscn` icindeki 10 marker mevcut kavrama gorunumune "bake"
edilmistir, yani kavrama kapatildiginda gorunum degismez.

Kavramayi yeniden bake etmek (grip geometrisi/radius degistiyse):

1. `IK_character/hand_rig.grip_wrap = true` yap (marker'lar her karede kavrama
   hedefine yazilir; ekranda gorunum ayni kalir).
2. `grip_wrap = false` yap ve sahneyi kaydet: marker'lar artik o kavramayi tutar.

Silaha ozel parmak kalibrasyonu (marker'dan daha hassas) icin `FingersRight/`
`FingersLeft/` grubunu silah sahnesine ekle; o silah takilinca digerlerini
otomatik olarak gecer.

## Parmak cozumu nerede calisir

`Armature/Skeleton3D/fingers_ik` (`scripts/ik/finger_ik.gd`,
`SkeletonModifier3D`) iskelet modifier zincirinin **son** halkasidir; kol IK'si
(`r_arm`/`l_arm`) ve el kopyalama (`*_hand_copy_trans`) calistiktan sonra
`hand_rig.solve_fingers_in_modifier()`'i cagirir. Bu sira korunmali: modifier
erken calisirsa parmaklar bir kare gecikmeli/eski el pozuna gore cozulur.
Ayni nedenle parmak cozumu `_process` icinden kemik pozu yazmaz; yazarsa
editorde render'a yansimaz (iskelet pozlari kare sonunda geri alinir).

## IK ve animasyon uyumu

`scripts/ik/hand_rig.gd` tek master'dir:

```
player_controller -> r_arm_marker          (sag el hedefi)
silah GripLeft    -> l_arm_marker          (sol el destek hedefi)
silah GripRight/Left + parmak markerlari -> parmak uclari (kod IK)
```

`arm_ik_influence` / `finger_ik_influence` 0 oldugunda kemikler animasyonun
biraktigi yerden devam eder; `auto_anim_yield` acikken oynayan animasyon
kol/el/parmak kemiklerine dokunuyorsa IK kendiliginden cekilir (sarjor
degistirme, surgu cekme, tetik animasyonlari kendi pozunu gosterir).
`anim_influence` sozlugu ile animasyon adi basina zorlanabilir:
`{"reload": 0.0}`.

## Editor onizlemesi (ik_character.tscn tek basina acilinca)

`ik_character.tscn` acildiginda silah elde gorunur: `hand_rig.preview_weapon`
isaretli sahneyi el soketine gecici olarak ornekler. Ornek dugumun `owner`'i
yoktur; sahne kaydina yazilmaz, oyunda kullanilmaz. `weapons/<ad>/<ad>.tscn`
kaydedilince onizleme kendini tazeler, yani el/silah kalibrasyonu editorde canli
yapilir.

- Kol IK'si editorde kendiliginden islenmez. `hand_rig` her karede iskelete
  `NOTIFICATION_UPDATE_SKELETON` gondererek kol + parmak cozumunu canli hale
  getirir: marker'i suruklersen kollar ve parmaklar aninda takip eder.
- `EyeAnchor` (Marker3D): kameranin karakter lokalindeki referansi. Oyundaki
  `Player/CameraPivot` ile ayni yerde olmali (olculerek yazildi).
- `r_arm_marker`'in sahnedeki pozu OYUNDAKI dinlenme tutusudur ("authored").
  `player_controller` o pozu okuyup kamera cercevesine tasir; sabit sayi yoktur,
  yani editorde ne gorunuyorsa oyunda birebir aynidir.
- `ads_hand_delta` (`player_controller`): nisan alirken elin goz cercevesindeki
  kaymasi; authored pozun uzerine eklenir.
- `preview_weapon`'i baska bir silaha cevirerek o silahi editorde kalibre et.
- Onizleme sirasinda sol el marker'i (`l_arm_marker`) oyundaki gibi silaha
  oturtulur. Sahneyi kaydedersen authored sol el pozu bu anki tutusa esitlenir
  (zararsiz; oyunda zaten silah belirler).

## Kol pole (dirsek) ve tepme

- `auto_pole` acikken `r_arm_pole` / `l_arm_pole` her karede el hedefinden
  turetilir: `target + rig.basis * pole_offset_<side>`. Boylece silah/bilek
  donerken dirsek karakter cercevesinde kalir; pole silahin roll'una bagli
  olmadigi icin kol ters donmez. Ince ayar: `pole_offset_r/l` (rig lokal:
  -X oyuncunun sagi, -Y asagi, -Z geri).
- `player_controller.hand_recoil` (0..1, varsayilan 0.55): silahin tepme kaymasi
  (`weapon.recoil_pos_cur`) el hedefine de eklenir. Boylece sag kol + el +
  parmaklar tepmeye birlikte gider; 0 = tepme yalniz silahta, kol hic oynamaz.
  Silahin donusu degismez (yalniz konum katkisi).

## Olcum / regresyon

`dev_test/rig_probe.tscn` (kabuktan, editoru etkilemeden):

```
Godot --path . res://dev_test/rig_probe.tscn
```

Cikti: `user://probe_out.txt`. Parmak/kol olcumleri iskelet modifier gecisi
ICINDEN kaydedilir (`hand_rig.debug_prints = true` -> `debug_tips`,
`debug_arm`), cunku modifier gecisi disinda `Skeleton3D.get_bone_global_pose`
temel (T-poz) kemigi dondurur ve yaniltici olur.

## Yeni silah ekleme

1. `weapons/<ad>/` klasoru ac.
2. `<ad>.tscn` olustur (g18.tscn'den kopyala), yukaridaki duzeni koru.
3. Kok dugume `metadata/weapon_id = "<ad>"` ekle.
4. `WeaponManager.equip("<ad>")` ile tak (varsayilan: `default_weapon`).
   Baska dosyada degisiklik gerekmez.
