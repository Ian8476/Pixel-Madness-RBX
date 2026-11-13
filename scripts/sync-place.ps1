# sync-place.ps1 - meter el codigo en el place SIN Rojo, para poder playtestear.
#
# ================================ LEER ESTO ==================================
# Esto NO es Rojo y no lo reemplaza. Es una copia de UNA SOLA DIRECCION, del repo
# al place, hecha para poder apretar Play en una maquina que no tiene la toolchain.
#
#   - No hay sync continuo: cada cambio en el repo exige volver a correr esto.
#   - No hay vuelta: lo que edites DENTRO de Studio se pierde en la proxima corrida.
#     La regla 1 del proyecto sigue en pie, y aca pesa mas que nunca: el codigo NUNCA
#     se edita en Studio.
#   - El place queda con una copia que envejece. Si dudas de si esta al dia, corre
#     esto de nuevo: es idempotente (borra el arbol viejo y lo rehace).
#
# El camino bueno sigue siendo `rojo serve`.
# =============================================================================
#
# USO
#   pwsh scripts/sync-place.ps1
#   -> genera build/place-install.luau
#   -> copiar TODO y pegarlo en la barra de comandos de Studio
#   -> aparecen ReplicatedStorage/Shared, ServerScriptService/Server y
#      StarterPlayerScripts/Client, y ya se puede apretar Play
#
# Respeta el mapeo de default.project.json y su globIgnorePaths (no copia *.spec.luau).

param(
    [string]$Repo = (Split-Path -Parent $PSScriptRoot),
    [string]$Out
)

if (-not $Out) { $Out = Join-Path $Repo "build\place-install.luau" }

$outDir = Split-Path -Parent $Out
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Force -Path $outDir | Out-Null }

$roots = @(
    @{ dir = "src\shared"; path = "Shared" }
    @{ dir = "src\server"; path = "Server" }
    @{ dir = "src\client"; path = "Client" }
)

# Elige un nivel de corchete largo que no aparezca en el contenido del archivo.
function LongString([string]$text) {
    for ($level = 0; $level -lt 8; $level++) {
        $eq = "=" * $level
        if (-not $text.Contains("]$eq]")) {
            return "[$eq[`n$text`n]$eq]"
        }
    }
    throw "no se encontro un delimitador seguro"
}

# X.server.luau -> Script, X.client.luau -> LocalScript, el resto -> ModuleScript.
function ClassFor([string]$fileName) {
    if ($fileName -like "*.server.luau") { return "Script" }
    if ($fileName -like "*.client.luau") { return "LocalScript" }
    return "ModuleScript"
}

function BaseName([string]$fileName) {
    return ($fileName -replace '\.(server|client)\.luau$', '') -replace '\.luau$', ''
}

$containers = New-Object System.Collections.Generic.List[object]
$scripts = New-Object System.Collections.Generic.List[object]

function Walk([string]$dir, [string]$robloxPath) {
    # Una carpeta con init.luau se convierte en ModuleScript, igual que en Rojo.
    $initFile = Join-Path $dir "init.luau"
    $hasInit = Test-Path -LiteralPath $initFile

    $containers.Add([pscustomobject]@{
        path  = $robloxPath
        src   = if ($hasInit) { Get-Content -LiteralPath $initFile -Raw } else { $null }
        depth = ($robloxPath -split "/").Count
    })

    foreach ($file in Get-ChildItem -LiteralPath $dir -Filter *.luau -File) {
        if ($file.Name -eq "init.luau") { continue }
        if ($file.Name -like "*.spec.luau") { continue }

        $scripts.Add([pscustomobject]@{
            path  = "$robloxPath/$(BaseName $file.Name)"
            class = ClassFor $file.Name
            src   = Get-Content -LiteralPath $file.FullName -Raw
        })
    }

    foreach ($child in Get-ChildItem -LiteralPath $dir -Directory) {
        Walk $child.FullName "$robloxPath/$($child.Name)"
    }
}

foreach ($root in $roots) {
    Walk (Join-Path $Repo $root.dir) $root.path
}

$sb = New-Object System.Text.StringBuilder

[void]$sb.AppendLine('-- GENERADO por scripts/sync-place.ps1 - copia del repo al place.')
[void]$sb.AppendLine('-- NO editar el codigo resultante dentro de Studio: se pierde al resincronizar.')
[void]$sb.AppendLine('local ReplicatedStorage = game:GetService("ReplicatedStorage")')
[void]$sb.AppendLine('local ServerScriptService = game:GetService("ServerScriptService")')
[void]$sb.AppendLine('local StarterPlayer = game:GetService("StarterPlayer")')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('local ROOT_PARENTS = {')
[void]$sb.AppendLine('    Shared = ReplicatedStorage,')
[void]$sb.AppendLine('    Server = ServerScriptService,')
[void]$sb.AppendLine('    Client = StarterPlayer:WaitForChild("StarterPlayerScripts"),')
[void]$sb.AppendLine('}')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('for name, parent in ROOT_PARENTS do')
[void]$sb.AppendLine('    local existing = parent:FindFirstChild(name)')
[void]$sb.AppendLine('    if existing then existing:Destroy() end')
[void]$sb.AppendLine('end')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('local byPath = {}')
[void]$sb.AppendLine('local count = 0')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('local function place(path, class, source)')
[void]$sb.AppendLine('    local parts = string.split(path, "/")')
[void]$sb.AppendLine('    local name = parts[#parts]')
[void]$sb.AppendLine('    local parent')
[void]$sb.AppendLine('    if #parts == 1 then')
[void]$sb.AppendLine('        parent = ROOT_PARENTS[name]')
[void]$sb.AppendLine('    else')
[void]$sb.AppendLine('        parent = byPath[table.concat(parts, "/", 1, #parts - 1)]')
[void]$sb.AppendLine('    end')
[void]$sb.AppendLine('    if not parent then error("sin padre para " .. path) end')
[void]$sb.AppendLine('    local instance = Instance.new(class)')
[void]$sb.AppendLine('    instance.Name = name')
[void]$sb.AppendLine('    if source then instance.Source = source end')
[void]$sb.AppendLine('    instance.Parent = parent')
[void]$sb.AppendLine('    byPath[path] = instance')
[void]$sb.AppendLine('    count += 1')
[void]$sb.AppendLine('end')
[void]$sb.AppendLine('')

# Padres antes que hijos.
foreach ($container in ($containers | Sort-Object depth, path)) {
    if ($null -eq $container.src) {
        [void]$sb.AppendLine("place(`"$($container.path)`", `"Folder`")")
    }
    else {
        [void]$sb.AppendLine("place(`"$($container.path)`", `"ModuleScript`", $(LongString $container.src))")
    }
}

foreach ($script in ($scripts | Sort-Object path)) {
    [void]$sb.AppendLine("place(`"$($script.path)`", `"$($script.class)`", $(LongString $script.src))")
}

[void]$sb.AppendLine('')
[void]$sb.AppendLine('print(string.format("PixelMadness: %d objetos instalados en el place.", count))')

Set-Content -LiteralPath $Out -Value $sb.ToString() -Encoding UTF8

"Instalador en $Out"
"$($containers.Count) contenedores + $($scripts.Count) scripts. Pegalo en la barra de comandos de Studio."
