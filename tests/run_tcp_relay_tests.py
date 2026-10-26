"""Host integration checks. Not a HarmonyOS SDK/device test."""
import pathlib
import subprocess
import tempfile
import os
root = pathlib.Path(__file__).resolve().parents[1]
cpp = root / 'entry/src/main/cpp'
with tempfile.TemporaryDirectory(prefix='kujiequ-tcp-') as build:
    build = pathlib.Path(build)
    flags = ['-g', '-fsanitize=address,undefined', '-fno-omit-frame-pointer', '-I' + str(cpp), '-I' + str(cpp/'lwip_port'), '-I' + str(cpp/'vendor/lwip/src/include')]
    objects = []
    sources = sorted((cpp/'vendor/lwip/src/core').glob('*.c')) + sorted((cpp/'vendor/lwip/src/core/ipv4').glob('*.c'))
    for src in sources:
        obj = build / (src.stem + '.o')
        subprocess.run(['gcc', '-std=c11', *flags, '-c', str(src), '-o', str(obj)], check=True)
        objects.append(str(obj))
    exe = str(build/'relay_test')
    subprocess.run(['g++', '-std=c++17', '-Wall', '-Wextra', '-Werror', '-pthread', *flags, str(cpp/'tcp_relay.cpp'), str(root/'tests/tcp_relay_test.cpp'), *objects, '-o', exe], check=True)
    subprocess.run([exe], check=True, timeout=45, env={**os.environ, 'ASAN_OPTIONS':'detect_leaks=0'})
