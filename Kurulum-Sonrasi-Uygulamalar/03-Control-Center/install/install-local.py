#!/usr/bin/python3
"""One-time administrator install. No disk formatting or boot-order changes."""
import datetime, hashlib, json, os, pathlib, plistlib, pwd, shutil, stat, subprocess, sys, tempfile
P=pathlib.Path
BASE=P('/Library/Application Support/G870ControlCenter')
APP=P('/Applications/G870ControlCenter.app')
DAEMON=P('/Library/LaunchDaemons/local.g870.hardware.plist')
SOCKET='/var/run/g870-control.sock'

def run(*args):
    return subprocess.run(args,check=True,capture_output=True,text=True).stdout

def disk_info(device):
    return plistlib.loads(subprocess.check_output(['/usr/sbin/diskutil','info','-plist',str(device)]))

def locate_internal_efi():
    root=disk_info('/System/Volumes/Data')
    reference=root.get('APFSContainerReference')
    if not reference: raise RuntimeError('macOS APFS konteyneri belirlenemedi; disk değiştirilmedi.')
    containers=plistlib.loads(subprocess.check_output(['/usr/sbin/diskutil','apfs','list','-plist']))['Containers']
    matches=[c for c in containers if c.get('ContainerReference')==reference]
    if len(matches)!=1 or len(matches[0].get('PhysicalStores',[]))!=1: raise RuntimeError('Tek fiziksel macOS diski doğrulanamadı.')
    store=matches[0]['PhysicalStores'][0]['DeviceIdentifier']
    whole=disk_info(store).get('ParentWholeDisk')
    if not whole or not disk_info(whole).get('Internal'): raise RuntimeError('macOS diski dahili değil; kurulum durdu.')
    listing=plistlib.loads(subprocess.check_output(['/usr/sbin/diskutil','list','-plist',whole]))
    partitions=listing['AllDisksAndPartitions'][0].get('Partitions',[])
    efi=[p['DeviceIdentifier'] for p in partitions if p.get('Content')=='EFI']
    if len(efi)!=1: raise RuntimeError('Dahili diskte tek EFI bölümü bulunamadı.')
    return efi[0]

def merge_config(config, entries):
    # Preserve all unrelated OpenCore and Microsoft settings.
    import copy
    result=copy.deepcopy(config)
    for section,pathkey in [('Kernel','BundlePath'),('ACPI','Path')]:
        entry=entries[section]; target=entry[pathkey]
        old=result[section]['Add']
        indexes=[i for i,e in enumerate(old) if e.get(pathkey)==target]
        position=indexes[0] if indexes else len(old)
        result[section]['Add']=[e for e in old if e.get(pathkey)!=target]
        result[section]['Add'].insert(position,entry)
    return result

def verify_payload(payload):
    manifest=json.loads((payload/'manifest.json').read_text())
    expected=set(manifest)
    actual={str(p.relative_to(payload)) for p in payload.rglob('*') if p.is_file() and p.name!='manifest.json'}
    if actual!=expected: raise RuntimeError('Kurulum paketi dosya listesi farklı.')
    for relative,digest in manifest.items():
        file=payload/relative
        if file.is_symlink() or hashlib.sha256(file.read_bytes()).hexdigest()!=digest: raise RuntimeError('Paket doğrulaması başarısız: '+relative)
    for file in payload.rglob('*'):
        if file.is_symlink(): raise RuntimeError('Pakette sembolik bağlantı kabul edilmez.')

def owned_directory(path):
    if path.is_symlink(): raise RuntimeError('Hedef sembolik bağlantı: '+str(path))
    if path.exists() and path.stat().st_uid!=0: raise RuntimeError('Sistem klasörü root sahibi değil: '+str(path))
    path.mkdir(parents=True,exist_ok=True);os.chmod(path,0o755)

def root_tree(path):
    for file in [path,*path.rglob('*')]:
        if file.is_symlink(): raise RuntimeError('Hedefte sembolik bağlantı: '+str(file))
        os.chown(file,0,0)
        os.chmod(file,0o755 if file.is_dir() or file.name in ('G870Monitor','g870ctl','user-session.sh') else 0o644)

def install_efi(mount,payload,backup):
    efi=mount/'EFI';oc=efi/'OC';config=oc/'config.plist'
    if not config.is_file() or not (oc/'OpenCore.efi').is_file(): raise RuntimeError('EFI içinde mevcut OpenCore bulunamadı; üzerine başka EFI yazılmadı.')
    original=plistlib.loads(config.read_bytes())
    updated=merge_config(original,json.loads((payload/'entries.json').read_text()))
    backup.mkdir(parents=True,exist_ok=False)
    shutil.copytree(efi,backup/'EFI')
    changed=[oc/'Kexts/G870Bridge.kext',oc/'ACPI/SSDT-G870-RGB.aml',config]
    try:
        target=changed[0]
        if target.exists(): shutil.rmtree(target)
        shutil.copytree(payload/'G870Bridge.kext',target)
        shutil.copy2(payload/'SSDT-G870-RGB.aml',changed[1])
        staged=config.with_name('config.g870-new.plist')
        staged.write_bytes(plistlib.dumps(updated,sort_keys=False));plistlib.loads(staged.read_bytes())
        os.replace(staged,config)
        for source in (payload/'G870Bridge.kext').rglob('*'):
            if source.is_file() and source.read_bytes()!=(target/source.relative_to(payload/'G870Bridge.kext')).read_bytes(): raise RuntimeError('EFI sürücü kopyası doğrulanamadı.')
        if changed[1].read_bytes()!=(payload/'SSDT-G870-RGB.aml').read_bytes(): raise RuntimeError('EFI RGB kopyası doğrulanamadı.')
        if plistlib.loads(config.read_bytes())!=updated: raise RuntimeError('EFI yapılandırması doğrulanamadı.')
    except BaseException:
        for target in changed:
            if target.is_dir(): shutil.rmtree(target)
            elif target.exists(): target.unlink()
            old=backup/'EFI'/target.relative_to(efi)
            if old.is_dir(): shutil.copytree(old,target)
            elif old.exists(): shutil.copy2(old,target)
        raise

def main():
    if os.geteuid()!=0 or len(sys.argv)!=3: raise RuntimeError('Bu kurucuyu Yerel-Kurulum.command ile çalıştırın.')
    uid=int(sys.argv[2]);account=pwd.getpwuid(uid)
    if uid<501 or P('/dev/console').stat().st_uid!=uid: raise RuntimeError('Kurulumu açık macOS kullanıcı oturumundan başlatın.')
    if os.uname().machine != 'x86_64' or os.uname().release.split('.')[0] != '24': raise RuntimeError('Bu paket Intel macOS 15 / Darwin 24 içindir.')
    home=P(account.pw_dir);agent=home/'Library/LaunchAgents/local.g870.control-center.plist'
    if agent.is_symlink() or not agent.parent.resolve().is_relative_to(home.resolve()): raise RuntimeError('Oturum açılış yolu beklenmeyen bir konuma bağlı.')
    if subprocess.run(['/usr/bin/pgrep','-x','G870Monitor'],stdout=subprocess.DEVNULL).returncode==0: raise RuntimeError('Önce Control Center uygulamasını Command+Q ile kapatın.')
    source=P(sys.argv[1]).resolve();verify_payload(source)
    with tempfile.TemporaryDirectory(prefix='g870-install-',dir='/private/tmp') as temporary:
        payload=P(temporary)/'payload';shutil.copytree(source,payload);verify_payload(payload)
        device=locate_internal_efi()
        print('Hedef: macOS dahili diskindeki EFI — '+device,flush=True)
        run('/usr/sbin/diskutil','mount',device)
        mount=P(disk_info(device)['MountPoint'])
        if os.statvfs(mount).f_flag & os.ST_RDONLY:
            run('/usr/sbin/diskutil','unmount',device)
            run('/usr/sbin/diskutil','mount',device)
            mount=P(disk_info(device)['MountPoint'])
        if os.statvfs(mount).f_flag & os.ST_RDONLY: raise RuntimeError('EFI salt okunur kaldı; kurulum durdu.')
        owned_directory(BASE)
        stamp=datetime.datetime.now().strftime('%Y%m%d-%H%M%S')
        backup=BASE/'Backups'/stamp
        install_efi(mount,payload,backup)
        print('EFI yedeklendi ve Control Center dosyaları doğrulandı: '+str(backup),flush=True)
        # Stop the old agent before replacing the app and hardware helper.
        subprocess.run(['/bin/launchctl','bootout','gui/'+str(uid)+'/local.g870.control-center'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
        subprocess.run(['/bin/launchctl','bootout','system/local.g870.hardware'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
        if APP.is_symlink(): raise RuntimeError('Uygulama hedefi sembolik bağlantı.')
        if APP.exists():
            info=plistlib.loads((APP/'Contents/Info.plist').read_bytes())
            if info.get('CFBundleIdentifier')!='local.g870.ControlCenter': raise RuntimeError('Hedefte başka bir uygulama var.')
            shutil.move(str(APP),str(backup/'G870ControlCenter.app'))
        shutil.copytree(payload/'G870ControlCenter.app',APP);root_tree(APP)
        for name in ['g870ctl','user-session.sh']:
            target=BASE/name
            if target.is_symlink(): raise RuntimeError('Yardımcı hedefi sembolik bağlantı.')
            if target.exists(): shutil.copy2(target,backup/name)
            shutil.copy2(payload/name,target);os.chown(target,0,0);os.chmod(target,0o755)
        if DAEMON.is_symlink(): raise RuntimeError('Servis hedefi sembolik bağlantı.')
        if DAEMON.exists(): shutil.copy2(DAEMON,backup/DAEMON.name)
        daemon={'Label':'local.g870.hardware','ProgramArguments':[str(BASE/'g870ctl'),'serve',str(uid)],'UserName':'root','Sockets':{'Control':{'SockPathName':SOCKET,'SockPathOwner':uid,'SockPathGroup':account.pw_gid,'SockPathMode':0o600}},'ProcessType':'Interactive','ExitTimeOut':15,'StandardErrorPath':str(BASE/'hardware-error.log')}
        DAEMON.write_bytes(plistlib.dumps(daemon));os.chown(DAEMON,0,0);os.chmod(DAEMON,0o644)
        if not agent.parent.exists():
            agent.parent.mkdir(parents=True,exist_ok=True);os.chown(agent.parent,uid,account.pw_gid)
        if agent.exists():shutil.copy2(agent,backup/agent.name)
        login={'Label':'local.g870.control-center','ProgramArguments':['/bin/bash',str(BASE/'user-session.sh')],'RunAtLoad':True,'LimitLoadToSessionType':'Aqua','ProcessType':'Interactive'}
        with tempfile.NamedTemporaryFile(dir=agent.parent,prefix='.g870-agent-',delete=False) as staged:
            staged.write(plistlib.dumps(login));os.fchown(staged.fileno(),uid,account.pw_gid);os.fchmod(staged.fileno(),0o644)
            staged_name=staged.name
        os.replace(staged_name,agent)
        run('/bin/launchctl','bootstrap','system',str(DAEMON))
        # The login job must be registered in the existing user's GUI domain.
        run('/bin/launchctl','bootstrap','gui/'+str(uid),str(agent))
        state={'uid':uid,'efi_device':device,'backup':str(backup),'app':str(APP),'socket':SOCKET}
        (BASE/'installation.json').write_text(json.dumps(state,indent=2));os.chmod(BASE/'installation.json',0o644)
        print('\nKURULUM TAMAMLANDI. Uygulama açılıyor; sonraki girişlerde parola/Terminal gerekmez.\nUSB’yi çıkarmadan önce uygulamayı kontrol edin. Ardından bilgisayarı kapatıp USB olmadan dahili OpenCore ile açılışı deneyin.\n',flush=True)

if __name__=='__main__':
    try:main()
    except Exception as error:
        print('\nKURULUM TAMAMLANMADI: '+str(error),file=sys.stderr)
        if isinstance(error,subprocess.CalledProcessError):print(error.stderr,file=sys.stderr)
        sys.exit(1)
