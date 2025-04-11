import os

extensiones = {'.swift', '.xib', '.storyboard', '.plist', '.json', '.md'}
excluir_directorios = {'Pods', '.git', 'DerivedData', 'build', '.build'}

archivo_salida = 'proyecto_swift.txt'

with open(archivo_salida, 'w', encoding='utf-8') as fout:
    for root, dirs, files in os.walk('.'):
        # Excluir directorios no deseados
        dirs[:] = [
            d for d in dirs
            if d not in excluir_directorios
            and not d.startswith('.')
            and 'test' not in d.lower()
        ]

        for file in files:
            if os.path.splitext(file)[1] in extensiones:
                ruta = os.path.join(root, file)
                fout.write(f"\n\n===== {ruta} =====\n")
                try:
                    with open(ruta, 'r', encoding='utf-8', errors='ignore') as fin:
                        fout.write(fin.read())
                except Exception as e:
                    fout.write(f"[Error leyendo {ruta}: {e}]\n")