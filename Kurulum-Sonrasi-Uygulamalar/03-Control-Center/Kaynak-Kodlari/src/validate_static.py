from pathlib import Path
import subprocess,json,hashlib,plistlib
root=Path(__file__).resolve().parent.parent
binary=root/'build/G870Bridge.kext/Contents/MacOS/G870Bridge'
def symbols(args):
    result=subprocess.run(['/usr/bin/nm',*args],capture_output=True,text=True,check=True)
    if not result.stdout.strip(): raise RuntimeError('nm returned no symbols')
    return {line.split()[-1] for line in result.stdout.splitlines() if line.split()}
imports=symbols(['-u',str(binary)])
exports=symbols(['-gU','/System/Library/KernelCollections/BootKernelExtensions.kc'])
plistlib.loads((binary.parent.parent/'Info.plist').read_bytes())
report={'kind':'STATIC ONLY: not driver loading or hardware validation', 'imports':len(imports),'found_in_boot_collection':len(imports&exports),'missing':sorted(imports-exports),'binary_sha256':hashlib.sha256(binary.read_bytes()).hexdigest()}
(root/'static-validation.json').write_text(json.dumps(report,indent=2))
print(json.dumps(report,indent=2))
raise SystemExit(1 if report['missing'] else 0)
