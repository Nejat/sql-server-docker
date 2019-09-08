function convert-value {

    param (
        [parameter(ValueFromPipeline)]
        [string] $source
    )

    if ($source -eq "null" -or $null -eq $source)
    {
        return $null
    } else {
        [int] $result = [int]::MinValue

        if ([int]::TryParse($source, [ref]$result)) {
            return $result
        }

        [long] $result = [long]::MinValue

        if ([long]::TryParse($source, [ref]$result)) {
            return $result
        }

        [double] $result = [double]::MinValue

        if ([double]::TryParse($source, [ref]$result)) {
            return $result
        }

        [bool] $result = $false

        if ([bool]::TryParse($source, [ref]$result)) {
            return $result
        }

        [datetime] $result = [datetime]::MinValue

        if ([datetime]::TryParse($source, [ref]$result)) {
            return $result
        }

        [guid] $result = [guid]::Empty

        if ([guid]::TryParse($source, [ref]$result)) {
            return $result
        }

        return $source
    } 
}


function add-properties {

    param (
          [psobject]  $source
        , [hashtable] $newProperties
    )
    
    [hashtable] $combined = @{}

    $source.psobject.properties | ForEach-Object {

        $combined[$_.Name] = $_.Value
    }

    $newProperties.Keys | ForEach-Object {
        $combined[$_] = $newProperties[$_]
    }

    New-Object -TypeName psobject -Property $combined
}

function get-port-mapping {

    param (
        [int] $default = 1433
    )

    [int]  $port    = 0
    [bool] $invalid = $true

    Write-Host ""

    do {

        $value = Read-Host "enter a port to map 1433/tcp to host (enter to use $default)"

        if ($null -eq $value -or $value -eq "") {
            $port    = $default
            $invalid = $false
        } 
        else {
            try {
                $port = [int]$value
            }
            catch {
                $port = -1
            }
    
            $invalid = $port -lt 1024 -or $port -gt 65535

            if ($invalid) {
                Write-Host "`nyou must use a value tcp port between 1024 and 65535`n" -ForegroundColor Red
            }
        }
    } while ($invalid)

    $port
}

function read-json {

    param (
        [string] $sourceFile
    )
    
    Get-Content $sourceFile | Out-String | ConvertFrom-Json
}

function select-database {

    param (
        [string] $verb      = "Build"
      , [bool]   $allOption = $false
    )

    [object[]] $dbs = read-json ".\dbs.json"

    do {
        Clear-Host
        Write-Host "======== SQL Server Docker ========`n"

        [int] $choices = 0

        $dbs | ForEach-Object {

            $choices++

            $title = $_.title

            Write-Host "$choices $verb $title Image"
        }

        if ($allOption) {
            Write-Host "`nA: Press 'A' select all." -ForegroundColor DarkGray
        } else {
            Write-Host ""
        }

        Write-Host "Q: Press 'Q' to quit.`n" -ForegroundColor DarkGray

        $command = Read-Host "Choose a command"

        Write-Host ""

        if ($command -eq "q") {
            exit
        }

        if ($allOption -and $command -eq 'a') {
            return $dbs
        }
    } while ($command -lt 1 -or $command -gt $choices)

    [object] $selected = $dbs[$command - 1]

    if ($null -ne $selected.include) {

        [object[]] $includedDbs = $dbs | ForEach-Object {

            [object] $db = $_

            if ($null -ne $db.name -and $selected.include.Contains($db.name)) {
                $db | Select-Object "name", "backup", "sourceUrl"
            }
        }

        $selected = add-properties $selected @{ dbs = $includedDbs }
    }

    $selected
}

function get-backup {

    param 
    (
          [string] $title
        , [string] $backupFile
        , [string] $dbImageUrl
    )

    if (!(Test-Path $backupFile -PathType Leaf)) {

        Write-Host "retreiving backup image for $title ...`n"
    
        Invoke-WebRequest -OutFile $backupFile $dbImageUrl
    }
}

function copy-backup {

    param (
          [string] $image
        , [string] $title
        , [string] $backupFile
    )
    
    Write-Host "copy $title backup $backupFile to " -NoNewline
    Write-Host "image" -NoNewline -ForegroundColor Magenta
    Write-Host " '" -NoNewline
    Write-Host "$image" -NoNewline -ForegroundColor DarkYellow
    Write-Host "' ...`n"
    
    docker cp $backupFile ${image}:/var/opt/mssql/backup
}

function read-filelist {

    param 
    (
          [string] $image
        , [string] $pswd
        , [string] $backupFile
    )

    [string[]] $list = docker exec -it $image /opt/mssql-tools/bin/sqlcmd -S localhost `
                        -U SA -P "$pswd" `
                        -Q "RESTORE FILELISTONLY FROM DISK = '/var/opt/mssql/backup/$backupFile'"
    
    $lengths = $list[1].Split(' ') | ForEach-Object { $_.Length }

    [int] $start = 0 

    $columnNames = 0..($lengths.Length - 1) | ForEach-Object {
        
        [int] $col = $_
        
        if ($col -ne 0) { 
            $start += $lengths[$col - 1] + 1
        }
         
        $list[0].Substring($start, $lengths[$col]).Trim()  
    }
    
    2..($list.Length - 3) | ForEach-Object {
    
        [string] $row   = $_
        [int]    $start = 0 
    
        $values = 0..($lengths.Length - 1) | ForEach-Object {
         
            [int] $col = $_
    
            if ($col -ne 0) { 
                $start += $lengths[$col - 1] + 1
            }
    
            try {
                [string] $value = $list[$row].Substring($start, $lengths[$col]).Trim() 

                $value | convert-value
            }
            catch {
                [string] $columnName = $columnNames[$col]
                [int]    $size       = $list[$row].Length
                [int]    $len        = $lengths[$col]

                Write-Host "row: $row, size: $size, start: $start, len: $len"
                Write-Host "Failed on value '$value' column $col '$columnName': $_" -ForegroundColor Red
            }
        } 
 
        [hashtable] $properties = @{ }
    
        0..($lengths.Length - 1) | ForEach-Object { 
    
            [string] $col = $_
    
            try {
                $properties.Add($columnNames[$col], $values[$col])
            }
            catch {
                Write-Host "Failed on column $col '${columnNames[$col]}': $_" -ForegroundColor Red
            }
        }
    
        New-Object -TypeName psobject -Property $properties
    }
}

function convert-file-moves {

    param (
        [psobject[]] $files
    )

    $moves = $files | ForEach-Object {

        $file = $_

        [string] $logical  = $file.LogicalName
        [string] $physical = $file.PhysicalName.Split('\') | Select-Object -Last 1
    
        "MOVE '$logical' TO '/var/opt/mssql/data/$physical'"
    }

    [string]::Join(", ", $moves)
}

function restore-backup {

    param (
          [string] $image
        , [string] $pswd
        , [string] $title
        , [string] $db
        , [string] $backupFile
        , [string] $moves
    )
    
    Write-Host "restoring $title ...`n"
    
    docker exec -it $image /opt/mssql-tools/bin/sqlcmd `
        -S localhost -U SA -P "$pswd" `
        -Q "RESTORE DATABASE $db FROM DISK = '/var/opt/mssql/backup/$backupFile' WITH $moves"
    
    Write-Host ""
    
    docker exec -it $image /opt/mssql-tools/bin/sqlcmd `
        -S localhost -U SA -P "$pswd" `
        -Q "SELECT Name FROM sys.Databases"
    
    Write-Host ""
}

function restore-db {

    param 
    (
          [string] $image
        , [string] $pswd
        , [string] $title
        , [string] $db
        , [string] $backupFile
        , [string] $dbImageUrl
    )

    add-folder-to-container  $image "backup" "/var/opt/mssql/backup"

    get-backup $title $backupFile $dbImageUrl
    
    copy-backup $image $title $backupFile
    
    [psobject[]] $files = read-filelist $image $pswd $backupFile
    [string]     $moves = convert-file-moves $files

    restore-backup $image $pswd $title $db $backupFile $moves

    Remove-Item $backupFile

    docker exec ${image} rm -rf /var/opt/mssql/backup/$backupFile
}

function get-sa-password {
    
    Write-Host "`nsa password must pass sql server secure password rules`n" -ForegroundColor DarkCyan

    do {
        [System.Security.SecureString] $password1 = Read-Host -AsSecureString "enter secure sa password"
        [string]                       $password1 = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($password1))
        [System.Security.SecureString] $password2 = Read-Host -AsSecureString "enter secure sa password again"
        [string]                       $password2 = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($password2))
    
        $noMatch = $password1 -cne $password2
        $blank   = $password1 -eq ""

        if ($noMatch) {
            Write-Host "`nentered passwords" -NoNewline
            Write-Host " do no match`n" -ForegroundColor Red
        } 
    
        if ($blank) {
            Write-Host "`nsa password" -NoNewline
            Write-Host " can not be blank`n" -ForegroundColor Red
        }
    } while ($noMatch -or $blank)
    
    Write-Host "`nsuccessfully" -NoNewline -ForegroundColor Green
    Write-Host " entered matching passowrds `n"

    $password1
}

function remove-existing-container {

    param (
        [string] $image
    )

    [string] $confirm = Read-Host "continuing will remove any existing image named '$image' ('y' to continue)"

    if ($confirm -ne "y") {
        Write-Host ""

        return
    }

    docker container stop $image *> $null
    docker container rm $image   *> $null
    docker volume rm $image-data *> $null
}

function get-latest-image {

    Write-Host "pulling latest " -NoNewline
    Write-Host "sql server 2017" -NoNewline -ForegroundColor DarkBlue
    Write-Host " image" -NoNewline -ForegroundColor Magenta
    Write-Host "  ...`n"
    
    docker pull mcr.microsoft.com/mssql/server:2017-latest
}

function add-sql-container {

    param (
          [string] $image
        , [string] $pswd
        , [string] $sqlPort
    )

    get-latest-image

    Write-Host "`ncreating " -NoNewline
    Write-Host "sql server 2017" -NoNewline -ForegroundColor DarkBlue
    Write-Host " container" -NoNewline -ForegroundColor Magenta
    Write-Host " '" -NoNewline
    Write-Host "$image" -NoNewline -ForegroundColor DarkYellow
    Write-Host "' and a " -NoNewline
    Write-Host "data volume container" -NoNewline -ForegroundColor Magenta
    Write-Host " '" -NoNewline
    Write-Host "$image-data" -NoNewline -ForegroundColor DarkYellow
    Write-Host "' ... " -NoNewline

    [string] $capture = docker run -e "ACCEPT_EULA=Y" -e "SA_PASSWORD=$pswd" `
                            --name "$image" -p ${sqlPort}:1433 `
                            -v $image-data:/var/opt/mssql `
                            -d mcr.microsoft.com/mssql/server:2017-latest

    Write-Host "created $capture`n"
}

function add-folder-to-container {

    param (
          [string] $image
        , [string] $type
        , [string] $folder
    )

    Write-Host "create $type folder on '" -NoNewline
    Write-Host "$image" -NoNewline -ForegroundColor DarkYellow
    Write-Host "' ...`n"

    docker exec -it $image mkdir -p $folder
}

Export-ModuleMember -Function add-folder-to-container
Export-ModuleMember -Function add-sql-container
Export-ModuleMember -Function get-port-mapping
Export-ModuleMember -Function get-sa-password
Export-ModuleMember -Function read-json
Export-ModuleMember -Function remove-existing-container
Export-ModuleMember -Function restore-db
Export-ModuleMember -Function select-database