from pathlib import Path
import plistlib,shutil,subprocess
root=Path(__file__).resolve().parent.parent; build=root/'build'; app=root/'G870 Kamera Prototip.app'; shared='group.local.g870.camera'
def plist(path,value):
 path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(plistlib.dumps(value))
def bundle(path,name,identifier,kind,binary,extra):
 (path/'Contents/MacOS').mkdir(parents=True,exist_ok=True)
 shutil.copy2(build/binary,path/'Contents/MacOS'/name)
 p={'CFBundleExecutable':name,'CFBundleIdentifier':identifier,'CFBundleName':name,'CFBundlePackageType':kind,'CFBundleVersion':'0.4.0','CFBundleShortVersionString':'0.4','LSMinimumSystemVersion':'13.0'};p.update(extra);plist(path/'Contents/Info.plist',p)
 return path
cmio=bundle(app/'Contents/Library/SystemExtensions/local.g870.camera.ProviderProbe.systemextension','G870Provider','local.g870.camera.ProviderProbe','SYSX','G870Provider',{'NSSystemExtensionUsageDescription':'G870 Quanta live video experiment.','CMIOExtension':{'CMIOExtensionMachServiceName':shared+'.ProviderProbe'}})
dext=app/'Contents/Library/SystemExtensions/local.g870.camera.MatchProbe.dext';(dext/'Contents/MacOS').mkdir(parents=True,exist_ok=True);shutil.copy2(build/'G870MatchProbe',dext/'Contents/MacOS/G870MatchProbe');shutil.copy2(root/'src/Driver/Info.plist',dext/'Contents/Info.plist')
bundle(app,'G870Host','local.g870.camera.ActivationHost','APPL','G870Host',{'NSSystemExtensionUsageDescription':'Installs a local Quanta-only camera driver experiment; captures live frames only while selected.','NSPrincipalClass':'NSApplication','NSHighResolutionCapable':True})
common={'com.apple.security.app-sandbox':True,'com.apple.security.application-groups':[shared]}
host={**common,'com.apple.developer.system-extension.install':True,'com.apple.security.files.user-selected.read-write':True}
common['com.apple.security.device.usb']=True
plist(build/'Host.entitlements',host);plist(build/'CMIO.entitlements',common)
for path,ent in [(cmio,build/'CMIO.entitlements'),(dext,root/'src/Driver/Driver.entitlements'),(app,build/'Host.entitlements')]:
 subprocess.run(['/usr/bin/codesign','--force','--sign','-','--entitlements',str(ent),str(path)],check=True)
 subprocess.run(['/usr/bin/codesign','--verify','--strict',str(path)],check=True)
# Validate both exact interface personalities, including all mandatory identity keys.
p=plistlib.load(open(dext/'Contents/Info.plist','rb'));assert len(p['IOKitPersonalities'])==2
for index,sub in [(0,1),(1,2)]:
 m=p['IOKitPersonalities']['G870QuantaInterface'+str(index)]
 assert m['CFBundleIdentifier']==p['CFBundleIdentifier']=='local.g870.camera.MatchProbe'
 assert m['idVendor']==1032 and m['idProduct']==8349 and m['bInterfaceClass']==14
 assert m['bConfigurationValue']==1 and m['bInterfaceNumber']==index and m['bInterfaceSubClass']==sub
 assert m['IOProviderMergeProperties']=={'CameraAssistantBundleID':'local.g870.camera.ProviderProbe'}
 assert m['IOProbeScore']==9999
print('0.4 package scope and strict signatures verified; hardware matching untested.')
