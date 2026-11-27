import pathlib,subprocess,sys
for name in sys.argv[1:]:
 p=pathlib.Path(name)
 hdr=subprocess.check_output(["readelf","-h",str(p)],text=True)
 dyn=subprocess.check_output(["readelf","-d",str(p)],text=True)
 syms=subprocess.check_output(["readelf","-Ws",str(p)],text=True)
 rel=subprocess.check_output(["readelf","-r",str(p)],text=True)
 assert "DYN" in hdr and "Advanced Micro Devices X86-64" in hdr
 assert "(NEEDED)" not in dyn and "INTERP" not in subprocess.check_output(["readelf","-l",str(p)],text=True)
 assert "There are no relocations" in rel,rel
 assert not any(x in syms for x in ["__kernel_init","__patch_init","kernel_patch","kexec","__rtld_init"])
 assert p.stat().st_size>10000000
 print(p.name,"freestanding ELF / no SDK CRT or dynamic relocations")
