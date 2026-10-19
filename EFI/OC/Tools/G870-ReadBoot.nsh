@echo -off
echo G870 - GERCEK FIRMWARE KAYITLARI > FS0:\G870-Firmware-Sonuc.txt
echo BCFG BOOT DUMP >> FS0:\G870-Firmware-Sonuc.txt
bcfg boot dump -v >> FS0:\G870-Firmware-Sonuc.txt
echo EFI GLOBAL BOOT DEGISKENLERI >> FS0:\G870-Firmware-Sonuc.txt
dmpstore Boot* -guid 8BE4DF61-93CA-11D2-AA0D-00E098032B8C >> FS0:\G870-Firmware-Sonuc.txt
echo DOSYA TAMAMLANDI >> FS0:\G870-Firmware-Sonuc.txt
echo Sonuc FS0:\G870-Firmware-Sonuc.txt dosyasina kaydedildi.
echo Acilis sirasi veya kayitlar degistirilmedi.
echo Bir tusa basinca OpenCore menusune donulecek. macOS'u secin.
pause
exit
