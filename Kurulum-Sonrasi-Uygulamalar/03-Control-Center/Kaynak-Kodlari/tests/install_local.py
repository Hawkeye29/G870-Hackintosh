import importlib.util, pathlib, plistlib, tempfile, unittest
spec=importlib.util.spec_from_file_location('installer',pathlib.Path(__file__).parent.parent/'install/install-local.py')
installer=importlib.util.module_from_spec(spec);spec.loader.exec_module(installer)
P=pathlib.Path
class InstallerTests(unittest.TestCase):
 def test_merge_only_targets(self):
  config={'Kernel':{'Add':[{'BundlePath':'Lilu.kext','Enabled':True},{'BundlePath':'G870Bridge.kext','Enabled':False},{'BundlePath':'G870Bridge.kext','Enabled':True}]},'ACPI':{'Add':[{'Path':'Existing.aml','Enabled':True}]},'NVRAM':{'keep':'same'},'Misc':{'Boot':{'keep':True}}}
  entries={'Kernel':{'BundlePath':'G870Bridge.kext','Enabled':True},'ACPI':{'Path':'SSDT-G870-RGB.aml','Enabled':True}}
  result=installer.merge_config(config,entries)
  self.assertEqual(result['NVRAM'],config['NVRAM']);self.assertEqual(result['Misc'],config['Misc'])
  self.assertEqual(result['Kernel']['Add'],[config['Kernel']['Add'][0],entries['Kernel']]);self.assertEqual(len(config['Kernel']['Add']),3)
  self.assertEqual(result['ACPI']['Add'][0],config['ACPI']['Add'][0])
 def test_efi_backup_and_rollback(self):
  for fail in (False,True):
   with self.subTest(fail=fail),tempfile.TemporaryDirectory() as directory:
    root=P(directory);mount=root/'mount';payload=root/'payload';oc=mount/'EFI/OC';backup=root/'backup'
    (oc/'Kexts/G870Bridge.kext').mkdir(parents=True);(oc/'ACPI').mkdir()
    (mount/'EFI/Microsoft').mkdir();(mount/'EFI/Microsoft/bootmgfw.efi').write_bytes(b'windows')
    (oc/'OpenCore.efi').write_bytes(b'existing-opencore');(oc/'Kexts/G870Bridge.kext/old').write_bytes(b'old')
    original={'Kernel':{'Add':[]},'ACPI':{'Add':[]},'NVRAM':{'keep':'unchanged'}}
    (oc/'config.plist').write_bytes(plistlib.dumps(original))
    (payload/'G870Bridge.kext').mkdir(parents=True);(payload/'G870Bridge.kext/new').write_bytes(b'new')
    (payload/'entries.json').write_text('{"Kernel":{"BundlePath":"G870Bridge.kext","Enabled":true},"ACPI":{"Path":"SSDT-G870-RGB.aml","Enabled":true}}')
    if not fail:(payload/'SSDT-G870-RGB.aml').write_bytes(b'new-aml')
    if fail:
     with self.assertRaises(FileNotFoundError):installer.install_efi(mount,payload,backup)
     self.assertEqual(plistlib.loads((oc/'config.plist').read_bytes()),original)
     self.assertEqual((oc/'Kexts/G870Bridge.kext/old').read_bytes(),b'old')
     self.assertFalse((oc/'ACPI/SSDT-G870-RGB.aml').exists())
    else:
     installer.install_efi(mount,payload,backup)
     self.assertTrue((oc/'Kexts/G870Bridge.kext/new').exists())
     self.assertEqual(plistlib.loads((oc/'config.plist').read_bytes())['NVRAM'],original['NVRAM'])
    self.assertEqual((mount/'EFI/Microsoft/bootmgfw.efi').read_bytes(),b'windows')
    self.assertEqual((backup/'EFI/OC/OpenCore.efi').read_bytes(),b'existing-opencore')
unittest.main()
