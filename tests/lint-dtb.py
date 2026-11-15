#!/usr/bin/env python3
"""Device tree lint for the K114s repair: every gpio-reserved-ranges entry must fit its controller,
and the AP pin controller must expose exactly the pins the tree names (pin 80; 134 and 139 with the jack codec)."""
import struct, sys
def walk(b):
    magic,total,ost,ostr,_,ver,_,_,szstr,szst = struct.unpack_from('>10I',b); assert magic==0xd00dfeed
    strs=b[ostr:ostr+szstr]; p=ost; path=[]; nodes={}
    while True:
        tok=struct.unpack_from('>I',b,p)[0]; p+=4
        if tok==1:
            e=b.index(b'\0',p); path.append(b[p:e].decode()); p=(e+4)&~3; nodes['/'.join(path) or '/']={}
        elif tok==3:
            ln,no=struct.unpack_from('>II',b,p); p+=8; v=b[p:p+ln]; p=(p+ln+3)&~3
            nodes['/'.join(path) or '/'][strs[no:strs.index(b'\0',no)].decode()]=v
        elif tok==2: path.pop()
        elif tok==9: break
    return nodes
bad=0
for f in sys.argv[1:]:
    nodes=walk(open(f,'rb').read()); root=nodes['/'] if '/' in nodes else nodes['']
    compat=root['compatible'].split(b'\0')[0].decode(); exposed_ap=None
    for path,props in nodes.items():
        if 'gpio-reserved-ranges' not in props: continue
        r=struct.unpack('>%dI'%(len(props['gpio-reserved-ranges'])//4),props['gpio-reserved-ranges'])
        n=struct.unpack('>I',props['apple,npins'])[0] if 'apple,npins' in props else None
        reserved=set()
        for start,count in zip(r[0::2],r[1::2]):
            if n is not None and (start>=n or start+count>n): print(f'FAIL {f} {path}: range <{start} {count}> runs past {n} pins and would be ignored'); bad+=1
            reserved|=set(range(start,start+count))
        if n is not None:
            exposed=sorted(set(range(n))-reserved)
            if n==221: exposed_ap=exposed
            print(f'  {f.split("/")[-1]} {path.split("/")[-1]}: {n} pins, exposed {exposed if len(exposed)<12 else str(len(exposed))+" pins"}')
    blob=open(f,'rb').read()
    want=[80] if b'pci106b,1900' in blob else []
    if b'cirrus,cs42l84' in blob: want+=[134,139]  # the jack codec's interrupt and reset (dts/t6050-k114s-sound.dtsi)
    if b'pci17a0,9755' in blob: want+=[81]  # the SD reader's PERST# (dts/t6050-k114s-sd.dtsi)
    want.sort()
    if compat!='apple,k114s': print(f'FAIL {f}: root compatible {compat}'); bad+=1
    if exposed_ap is not None and exposed_ap!=want: print(f'FAIL {f}: AP pin controller exposes {exposed_ap}, expected {want}'); bad+=1
print('dtb lint:', 'FAILED' if bad else 'passed', f'({len(sys.argv)-1} trees)'); sys.exit(1 if bad else 0)
