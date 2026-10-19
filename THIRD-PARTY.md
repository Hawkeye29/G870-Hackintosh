# Üçüncü taraf bileşenler ve kaynak depoları

Aşağıda bu EFI'de etkin olan upstream kext'ler listelenmiştir. Sürümler paketteki `Info.plist` değerlerinden alınmıştır. Üçüncü taraf bileşenler ilgili sahiplerinin lisanslarıyla dağıtılır; ikili dosya paylaşımı için upstream lisans ve bildirim koşullarını okuyun. Repo bağlantısı tek başına lisans koşullarını yerine getirmez.

| Bileşen | EFI sürümü | Kaynak deposu |
|---|---:|---|
| Lilu | 1.7.3 | [acidanthera/Lilu](https://github.com/acidanthera/Lilu) |
| AMFIPass | 1.4.1 | [dhinakg/AMFIPass](https://github.com/dhinakg/AMFIPass) |
| AppleALC | 1.9.9 | [acidanthera/AppleALC](https://github.com/acidanthera/AppleALC) |
| BlueToolFixup | 2.7.3 | [acidanthera/BrcmPatchRAM](https://github.com/acidanthera/BrcmPatchRAM) |
| BrightnessKeys | Info.plist sürüm alanı yok | [acidanthera/BrightnessKeys](https://github.com/acidanthera/BrightnessKeys) |
| CpuTopologyRebuild | 2.0.2 | [b00t0x/CpuTopologyRebuild](https://github.com/b00t0x/CpuTopologyRebuild) |
| ECEnabler | 1.0.6 | [averycblack/ECEnabler](https://github.com/averycblack/ECEnabler) |
| IntelBTPatcher | 2.5.0 | [zxystd/IntelBluetoothFirmware](https://github.com/zxystd/IntelBluetoothFirmware) |
| IntelBluetoothFirmware | 2.5.0 | [zxystd/IntelBluetoothFirmware](https://github.com/zxystd/IntelBluetoothFirmware) |
| NVMeFix | 1.1.4 | [acidanthera/NVMeFix](https://github.com/acidanthera/NVMeFix) |
| RealtekRTL8111 | 2.4.2 | [Mieze/RTL8111_driver_for_OS_X](https://github.com/Mieze/RTL8111_driver_for_OS_X) |
| RestrictEvents | 1.1.7 | [acidanthera/RestrictEvents](https://github.com/acidanthera/RestrictEvents) |
| VirtualSMC | 1.3.9 | [acidanthera/VirtualSMC](https://github.com/acidanthera/VirtualSMC) |
| SMCBatteryManager | 1.3.9 | [acidanthera/VirtualSMC](https://github.com/acidanthera/VirtualSMC) |
| SMCLightSensor | 1.3.9 | [acidanthera/VirtualSMC](https://github.com/acidanthera/VirtualSMC) |
| SMCProcessor | 1.3.9 | [acidanthera/VirtualSMC](https://github.com/acidanthera/VirtualSMC) |
| SMCSuperIO | 1.3.9 | [acidanthera/VirtualSMC](https://github.com/acidanthera/VirtualSMC) |
| VoodooI2C | 2.9.1 | [VoodooI2C/VoodooI2C](https://github.com/VoodooI2C/VoodooI2C) |
| VoodooGPIO | 1.1 | [VoodooI2C/VoodooGPIO](https://github.com/VoodooI2C/VoodooGPIO) |
| VoodooI2CServices | 1.0 | [VoodooI2C/VoodooI2C](https://github.com/VoodooI2C/VoodooI2C) |
| VoodooInput | 1.1.7 | [VoodooI2C/VoodooInput](https://github.com/VoodooI2C/VoodooInput) |
| VoodooI2CHID | 1.0 | [VoodooI2C/VoodooI2CHID](https://github.com/VoodooI2C/VoodooI2CHID) |
| VoodooPS2Controller ve VoodooPS2Keyboard | 2.3.7 | [acidanthera/VoodooPS2](https://github.com/acidanthera/VoodooPS2) |
| WhateverGreen | 1.7.2 | [acidanthera/WhateverGreen](https://github.com/acidanthera/WhateverGreen) |
| XHCI-unsupported | 0.9.2 | [RehabMan/OS-X-USB-Inject-All](https://github.com/RehabMan/OS-X-USB-Inject-All) |
| AirportItlwm | 2.4.1 | [OpenIntelWireless/itlwm](https://github.com/OpenIntelWireless/itlwm) |
| OpenCore | Bu EFI kopyasındaki binary | [acidanthera/OpenCorePkg](https://github.com/acidanthera/OpenCorePkg) |

## EFI içinde bulunan, varsayılan yapılandırmada kapalı kext'ler

Bu dosyalar EFI klasöründe vardır fakat `config.plist` içinde `Enabled=false` durumundadır. Gerekli olmadıkça etkinleştirmeyin.

- `USBToolBox.kext`, `UTBDefault.kext` — [USBToolBox/USBToolBox](https://github.com/USBToolBox/USBToolBox)
- `itlwm.kext` — [OpenIntelWireless/itlwm](https://github.com/OpenIntelWireless/itlwm)

## Bu repoya özgü bileşenler

Aşağıdaki G870 bileşenleri upstream açık kaynak kext listesine dahil değildir. Bu pakette derlenmiş ikili dosya/ACPI tablosu bulunur; kaynak kod ve yeniden dağıtım lisansı ayrıca yayımlanmamıştır. Bunlar için kaynak ve lisans eklenmeden “açık kaynak” denmemelidir.

- `G870-I2C-51E8.kext` 1.0.0
- `G870-USBMap.kext` 1.0.1
- `G870Bridge.kext` 0.8.0
- `SSDT-G870-GPRW.aml`, `SSDT-G870-RGB.aml` ve diğer G870 yapılandırma parçaları

## Uygulamalar

- NullMoth 1401 Mac yardımcı uygulaması ve NVIDIA sürücüsü bu repoya dahil değildir. Kullanıcılar uygulamayı doğrudan [1401 deposundan](https://github.com/nullmoth/1401) edinmeli ve güncel lisans/bildirim koşullarını izlemelidir. Sürücü projesi: [NVIDIA macOS Driver](https://github.com/nullmoth/nvidia-macos-driver). Bu repo Windows kurucusunu ve sürücü payload'ını içermez.
- G870 Kamera Prototip, G870 Control Center ve yerel G870 kodu için ayrı kaynak/lisans bildirimi gerekir; upstream kext tablosu bu uygulamaları kapsamaz.
