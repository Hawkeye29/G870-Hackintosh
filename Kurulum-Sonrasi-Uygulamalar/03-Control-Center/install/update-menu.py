#!/usr/bin/python3
import datetime, importlib.util, os, pathlib, plistlib, pwd, shutil, subprocess, sys, tempfile
P=pathlib.Path
spec=importlib.util.spec_from_file_location('installer',P(__file__).with_name('install-local.py'))
installer=importlib.util.module_from_spec(spec);spec.loader.exec_module(installer)
def main():
    if os.geteuid()!=0 or len(sys.argv)!=3:raise RuntimeError('Menu-Cubugu-Guncelle.command ile çalıştırın.')
    uid=int(sys.argv[2]);account=pwd.getpwuid(uid)
    if uid<501 or P('/dev/console').stat().st_uid!=uid:raise RuntimeError('Açık kullanıcı oturumu doğrulanamadı.')
    base=installer.BASE;app=installer.APP
    if not installer.DAEMON.exists() or not (base/'installation.json').exists():raise RuntimeError('Önce Yerel-Kurulum.command ile temel kurulumu tamamlayın.')
    if subprocess.run(['/usr/bin/pgrep','-x','G870Monitor'],stdout=subprocess.DEVNULL).returncode==0:raise RuntimeError('Önce mevcut Control Center uygulamasını Command+Q ile kapatın.')
    installer.owned_directory(base)
    source=P(sys.argv[1]).resolve();installer.verify_payload(source)
    if app.is_symlink() or plistlib.loads((app/'Contents/Info.plist').read_bytes()).get('CFBundleIdentifier')!='local.g870.ControlCenter':raise RuntimeError('Kurulu uygulama doğrulanamadı.')
    with tempfile.TemporaryDirectory(prefix='g870-menu-',dir='/private/tmp') as temporary:
        staged=P(temporary)/'G870ControlCenter.app';shutil.copytree(source/'G870ControlCenter.app',staged)
        installer.root_tree(staged)
        subprocess.run(['/usr/bin/codesign','--verify','--strict',str(staged)],check=True)
        agent=P(account.pw_dir)/'Library/LaunchAgents/local.g870.control-center.plist'
        subprocess.run(['/bin/launchctl','bootout','gui/'+str(uid)+'/local.g870.control-center'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
        backup=base/'Backups'/('menu-'+datetime.datetime.now().strftime('%Y%m%d-%H%M%S'))
        backup.mkdir(parents=True,exist_ok=False)
        shutil.move(str(app),str(backup/'G870ControlCenter.app'))
        try:
            shutil.copytree(staged,app);installer.root_tree(app)
            subprocess.run(['/usr/bin/codesign','--verify','--strict',str(app)],check=True)
        except BaseException:
            if app.exists():shutil.rmtree(app)
            shutil.copytree(backup/'G870ControlCenter.app',app);raise
        subprocess.run(['/bin/launchctl','bootstrap','gui/'+str(uid),str(agent)],check=True)
        print('Menü çubuğu güncellemesi tamamlandı. Sağ üstte fan simgesini kullanın.\nTam pencere kapanınca uygulama ve ayarlar çalışmaya devam eder.\nEski uygulama yedeği: '+str(backup))
if __name__=='__main__':
    try:main()
    except Exception as error:print('GÜNCELLEME TAMAMLANMADI: '+str(error),file=sys.stderr);sys.exit(1)
