# bundle-tests.ps1 - correr la suite de tests SIN instalar la toolchain.
#
# PARA QUE EXISTE
# El camino normal es `lune run tests/run`, y es el que corre el CI. Pero Lune es una
# instalacion mas en una maquina que quiza solo tiene Studio, y hubo mas de una sesion
# de desarrollo bloqueada por eso. Studio YA es un interprete de Luau: este script
# empaqueta los modulos puros y las specs en un unico archivo autocontenido que se
# pega en la barra de comandos de Studio y devuelve el mismo reporte.
#
# USO
#   pwsh scripts/bundle-tests.ps1
#   -> genera build/tests-bundle.luau
#   -> abrir ese archivo, copiar TODO y pegarlo en la barra de comandos de Studio
#   -> el resultado sale en el Output
#
# LIMITES (leer antes de confiar en el resultado)
#   - Solo empaqueta lo que no toca la API de Roblox: `Constants`, `Shared/Logic/**`,
#     `Shared/Data/**` y las specs. Es exactamente el mismo alcance que tiene Lune,
#     porque es el mismo alcance que la regla de esas carpetas garantiza.
#   - `@lune/fs` se simula leyendo el disco al generar. El test de cobertura de
#     `ContentData.spec` sigue comprobando lo que dice comprobar.
#   - La lista de modulos y de specs es explicita, igual que en `tests/run.luau`:
#     si agregas un modulo a `Shared/Logic/`, hay que sumarlo abajo. Los de
#     `Shared/Data/` se descubren solos.
#   - Esto NO reemplaza al CI. El CI usa Lune, que es la fuente de verdad.

param(
    [string]$Repo = (Split-Path -Parent $PSScriptRoot),
    [string]$Out
)

if (-not $Out) { $Out = Join-Path $Repo "build\tests-bundle.luau" }

$outDir = Split-Path -Parent $Out
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Force -Path $outDir | Out-Null }

# Quita comentarios de linea completa y bloques --[[ ]]. Se deja intacto lo que va al
# final de una linea de codigo: quitarlo pedirïa entender strings y no vale la pena.
function Strip-Comments([string[]]$lines) {
    $result = New-Object System.Collections.Generic.List[string]
    $inBlock = $false
    foreach ($line in $lines) {
        $trimmed = $line.Trim()
        # Ojo: `-like` trata `[` como comodin, por eso aca va StartsWith/Contains.
        if ($inBlock) {
            if ($trimmed.Contains("]]")) { $inBlock = $false }
            continue
        }
        if ($trimmed -match '^--\[\[.*\]\]\s*$') { continue }
        if ($trimmed.StartsWith("--[[")) { $inBlock = $true; continue }
        if ($trimmed.StartsWith("--")) { continue }
        if ($trimmed -eq "") { continue }
        $result.Add($line)
    }
    return $result
}

function Rewrite-Requires([string[]]$lines) {
    $result = New-Object System.Collections.Generic.List[string]
    foreach ($line in $lines) {
        # Las librerias de Lune van PRIMERO: la regex generica de abajo tambien casa
        # con "@lune/fs" (se queda con el ultimo segmento) y lo convertiria en un
        # modulo inexistente.
        $new = $line -replace 'require\("@lune/fs"\)', '__LUNE_FS'
        $new = [regex]::Replace($new, 'require\("(?:[^"]*/)?([A-Za-z0-9_.]+?)(?:\.spec)?"\)', '__M_$1')
        $result.Add($new)
    }
    return $result
}

function Emit-Module([string]$localName, [string]$path) {
    $lines = Rewrite-Requires (Strip-Comments (Get-Content -LiteralPath $path))
    $body = ($lines -join "`n")
    # `export type` solo vale a nivel de modulo; dentro del closure se degrada a
    # `type`, que queda local a ese closure y por lo tanto no choca con otros modulos.
    $body = $body -replace '(?m)^(\s*)export type', '$1type'
    return "local __M_$localName = (function()`n$body`nend)()`n"
}

function Dir-Literal([string]$dir) {
    $names = Get-ChildItem -LiteralPath $dir -Filter *.luau | ForEach-Object { '"' + $_.Name + '"' }
    return "{ " + ($names -join ", ") + " }"
}

$weaponsDir = Join-Path $Repo "src\shared\Data\Weapons"
$charactersDir = Join-Path $Repo "src\shared\Data\Characters"
$enemiesDir = Join-Path $Repo "src\shared\Data\Enemies"

$sb = New-Object System.Text.StringBuilder

[void]$sb.AppendLine('-- GENERADO por scripts/bundle-tests.ps1 - no editar a mano.')
[void]$sb.AppendLine('-- Se guarda el print de verdad ANTES de taparlo: el Runner escribe con `print`,')
[void]$sb.AppendLine('-- se junta todo en memoria y recien al final se vuelca al Output de una sola vez.')
[void]$sb.AppendLine('local __realPrint = print')
[void]$sb.AppendLine('local __output = {}')
[void]$sb.AppendLine('local print = function(...)')
[void]$sb.AppendLine('    local parts = {}')
[void]$sb.AppendLine('    for index = 1, select("#", ...) do')
[void]$sb.AppendLine('        table.insert(parts, tostring((select(index, ...))))')
[void]$sb.AppendLine('    end')
[void]$sb.AppendLine('    table.insert(__output, table.concat(parts, " "))')
[void]$sb.AppendLine('end')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('local __LUNE_FS = {')
[void]$sb.AppendLine('    readDir = function(path)')
[void]$sb.AppendLine('        if path == "src/shared/Data/Weapons" then return ' + (Dir-Literal $weaponsDir) + ' end')
[void]$sb.AppendLine('        if path == "src/shared/Data/Characters" then return ' + (Dir-Literal $charactersDir) + ' end')
[void]$sb.AppendLine('        if path == "src/shared/Data/Enemies" then return ' + (Dir-Literal $enemiesDir) + ' end')
[void]$sb.AppendLine('        error("readDir sin simular: " .. tostring(path))')
[void]$sb.AppendLine('    end,')
[void]$sb.AppendLine('}')
[void]$sb.AppendLine('')

# Dependencias primero. Espejo de lo que requieren las specs.
$modules = @(
    @{ name = "Constants";      path = "src\shared\Constants.luau" }
    @{ name = "DifficultyMath"; path = "src\shared\Logic\DifficultyMath.luau" }
    @{ name = "SpreadMath";     path = "src\shared\Logic\SpreadMath.luau" }
    @{ name = "ContentSchema";  path = "src\shared\Logic\ContentSchema.luau" }
    @{ name = "Rng";            path = "src\shared\Logic\Rng.luau" }
    @{ name = "DungeonLayout";  path = "src\shared\Logic\DungeonLayout.luau" }
    @{ name = "EnemyTactics";   path = "src\shared\Logic\EnemyTactics.luau" }
    @{ name = "LobbyRules";     path = "src\shared\Logic\LobbyRules.luau" }
    @{ name = "Runner";         path = "tests\Runner.luau" }
)

foreach ($file in (Get-ChildItem -LiteralPath $weaponsDir -Filter *.luau | Where-Object { $_.BaseName -ne "init" })) {
    $modules += @{ name = $file.BaseName; path = "src\shared\Data\Weapons\$($file.Name)" }
}
foreach ($file in (Get-ChildItem -LiteralPath $charactersDir -Filter *.luau | Where-Object { $_.BaseName -ne "init" })) {
    $modules += @{ name = $file.BaseName; path = "src\shared\Data\Characters\$($file.Name)" }
}
foreach ($file in (Get-ChildItem -LiteralPath $enemiesDir -Filter *.luau | Where-Object { $_.BaseName -ne "init" })) {
    $modules += @{ name = $file.BaseName; path = "src\shared\Data\Enemies\$($file.Name)" }
}

foreach ($module in $modules) {
    [void]$sb.AppendLine((Emit-Module $module.name (Join-Path $Repo $module.path)))
}

# Mismo orden que tests/run.luau
$specs = @(
    "Constants", "DifficultyMath", "SpreadMath", "ContentSchema",
    "ContentData", "Rng", "DungeonLayout", "EnemyTactics", "LobbyRules"
)

foreach ($spec in $specs) {
    [void]$sb.AppendLine((Emit-Module "SPEC_$spec" (Join-Path $Repo "tests\specs\$spec.spec.luau")))
}

[void]$sb.AppendLine('local __specs = {')
foreach ($spec in $specs) {
    [void]$sb.AppendLine("    __M_SPEC_$spec,")
}
[void]$sb.AppendLine('}')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('local __ok, __err = pcall(function()')
[void]$sb.AppendLine('    local passed = __M_Runner.run(__specs)')
[void]$sb.AppendLine('    table.insert(__output, passed and "RESULTADO: TODO VERDE" or "RESULTADO: HAY FALLOS")')
[void]$sb.AppendLine('end)')
[void]$sb.AppendLine('if not __ok then table.insert(__output, "EL RUNNER EXPLOTO: " .. tostring(__err)) end')
[void]$sb.AppendLine('__realPrint(table.concat(__output, "\n"))')

Set-Content -LiteralPath $Out -Value $sb.ToString() -Encoding UTF8

$lineCount = (Get-Content -LiteralPath $Out | Measure-Object -Line).Lines
"Bundle escrito en $Out ($lineCount lineas)."
"Pegalo entero en la barra de comandos de Studio para ver el reporte en el Output."
