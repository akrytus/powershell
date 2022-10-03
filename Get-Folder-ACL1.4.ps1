<# 
NTFS Folder Permissions
Author: Aaron Krytus
Date: 9/12/22
Version: 1.0 (9/12/22) - Get NTFS permissions for a root folder recursively
Version: 1.1 (9/12/22) - Progress Bar for Folder Collection and ACL Collection, logging and error traping
Version: 1.2 (9/13/22) - Report formating 
Version: 1.3 (9/13/22) - Estimated time and time left, check for elevated permissions
Version: 1.4 (9/15/22) - Run parallel jobs in runspace instead of PSJob
Version: 1.5 (TBA)     - User input (RootFolder) and verify it exists, set default output location and give option to agree or change




Notes:
    • Ignores the following Users/Accounts:
        ○ BUILTIN (Local accounts)
        ○ S-* (Unidentified accounts)
        ○ CREATOR (This permission is always full control)
        ○ NT AUTHORITY (System accounts)
    
    • Excel Formatting (recommended):
		○ Open .csv file
		○ Save As "Excel Workbook"
		○ Create table including all data (Format Table->Second table down(1x2)->A1->Last Cell)
        ○ Freeze Panes (View->Freeze Panes->Top Row)
#>


#Functions
#===========================
function Check-IsElevated {
    #Check if PowerShell is runninng as Administrator
    $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object System.Security.Principal.WindowsPrincipal($id)
    if ($p.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)){
       Write-Host "Script running as Admin" -ForegroundColor Green
    }      
    else{
        Write-Host "Not running with elevated permissions!" -ForegroundColor Red
        $flag = "True"}
    Return $flag
 }

function Get-NTFS-ACL {
    #Edit These Variables
    $RootPath = "C:\Users"
    $LogPath = "C:\Temp"
    $OutputPath = "C:\Temp"


    #Variables
    $start = Get-Date
    $Error.clear
    $fnDateFormat = 'MMddyy' #Date format for Files
    $dtFormat = "dd-MMM-yyyy HH:mm:ss" #Date format for logs
    $OutFile = "$OutputPath\ACL-Permissions-$(Get-Date -Format $fnDateFormat).csv"
    $logs = "$LogPath\ACL-Permissions-$(Get-Date -Format $fnDateFormat).log"
    $x = [hashtable]::Synchronized(@{}) #Used to count folders and update progress
    $x.counter = -1 #Folder Counter

    #Update Log file
    Add-Content $logs -value "`n`n"
    Add-Content $logs -value "-------------------------------------------------"
    Add-Content $logs -value "$(Get-Date -Format $dtFormat)     Starting Script"

    #Verify or Create Folders
    #Log Folder
        try{
            if(!(Get-Item -Path "$LogPath" -ErrorAction SilentlyContinue)){ #Verify if the folder exists before creating it
                New-Item -Path $LogPath -ItemType "directory" #Folder DNE, create it
                Add-Content $logs -value "$(Get-Date -Format $dtFormat)     Creating Log folder: $LogPath"
            } 
            else {Add-Content $logs -value "$(Get-Date -Format $dtFormat)     Log Folder $LogPath already exists"} #Folder already exists
             
        }
        catch{ #Error creating folder
            Add-Content $logs -value "$(Get-Date -Format $dtFormat)     Creating folder $LogPath FAILED!!!"
            $Error | Out-File $logs -Append
        }

    #Output Folder
        try{
            if(!(Get-Item -Path "$OutputPath" -ErrorAction SilentlyContinue)){ #Verify if the folder exists before creating it
                New-Item -Path $OutputPath -ItemType "directory" #Folder DNE, create it
                Add-Content $logs -value "$(Get-Date -Format $dtFormat)     Creating Output folder: $OutputPath"
            } 
            else {Add-Content $logs -value "$(Get-Date -Format $dtFormat)     Output Folder $OutputPath already exists"} #Folder already exists
             
        }
        catch{ #Error creating folder
            Add-Content $logs -value "$(Get-Date -Format $dtFormat)     Creating folder $OutPath FAILED!!!"
            $Error | Out-File $logs -Append
        }


       
    #Create and start Job to collect folders in seperate runspace
    $counter=0 #For the Folder Colletion progress bar
    $getFoldersCode = {param ($RootPath); Get-ChildItem -Directory -Path $RootPath -Recurse -Force -ErrorAction SilentlyContinue}
    $newPowerShell = [PowerShell]::Create().AddScript($getFoldersCode).AddParameter('RootPath', $RootPath)
    $getFoldersJob = $newPowerShell.BeginInvoke()
        
    Clear-Host
    Write-Host "`n`n`n`n`n`nDepending on the number of folders,`nThis may take several minutes..." -ForegroundColor Gray
    Add-Content $logs -value "$(Get-Date -Format $dtFormat)     Collecting folders..."
    
    #Progress Bar and logs
    $starttimer = Get-Date
    While(-Not $getFoldersJob.IsCompleted){
        Write-Progress -Activity "Collecting Folders..." -PercentComplete $x
        if($counter -eq 100){$counter=1}
        else{Start-Sleep -Milliseconds 2000; $counter+=1}
        
        #Update logs every 5 minutes to show script is still running
        $checktimer = Get-Date; $timer = $checktimer - $starttimer
        if($timer.Minutes -gt 5){
            Add-Content $logs -value "$(Get-Date -Format $dtFormat)     Script is still collecting Folders..."
            $starttimer = Get-Date #Restart 15 minute timer        
        }
    }
    
    #Get Job results and Clean up (GetFoldersJob)
    Write-Progress -Activity "Collecting Folders..." -Completed
    $Folders = $newPowerShell.EndInvoke($getFoldersJob) # Store results from job (All the folders)
    $newPowerShell.Dispose() #Clean up job
    
    
    #Estimated Time
    $FolderCount = $Folders.Count #Required to add logging below
    $estimatedTime = [Math]::Floor($FolderCount / 180) #Round down - Last run avg was 180 folders per minute
    if($estimatedTime -gt 60){$estimatedTime = [Math]::Round($estimatedTime/60,2); $timeFormat = " Minutes"}
    else {$timeFormat = " Seconds"} #Display number of minutes
    if($estimatedTime -gt 60){$estimatedTime = [Math]::Round($estimatedTime/60,2); $timeFormat = " Hours"
        if($estimatedTime -gt 24){$estimatedTime = [Math]::Round($estimatedTime/24,2); $timeFormat = " Days"}}
    
    
    #Update Screen and Logs with estimated time
    Write-Host "`n`nFound " -NoNewLine; Write-Host $Folders.count -ForegroundColor Yellow -NoNewline; Write-Host " folders."
    Add-Content $logs -value "$(Get-Date -Format $dtFormat)     Found $FolderCount folders"
    Write-Host "Estimated time to complete: " -NoNewLine; Write-Host $estimatedTime -ForegroundColor Yellow -NoNewline; Write-Host $timeFormat
    Add-Content $logs -value "$(Get-Date -Format $dtFormat)     Estimated time to complete: $estimatedTime $timeFormat"
    Read-Host "`n`nPress any key to Continue"
    Write-Host "`n`n`n`n`n`nCollecting ACLs..." -ForegroundColor Gray
    Add-Content $logs -value "$(Get-Date -Format $dtFormat)     Collecting ACLs..."
    
    
    #Start Timers and counters
    $starttimer = Get-Date #Start 15 minute timer for Logging
    $updateTimer = Get-Date #Start 1 minute timer to Update remaining time left
    Clear-Host     
    
    
    #Collect ACLs - Create and start Job to collect ACLs in seperate runspace
    $getACLCode = {   
        param ($Folders, $x)
        $Output = @()     #Create Object Table for CSV Output
        foreach($Folder in $Folders) {
            $x.counter += 1 #Counting Folders for progress
            #Collect Folder ACL
            $Acl = Get-Acl -Path $Folder.FullName -ErrorAction SilentlyContinue
    
            #Owner (Parent)
            if($Acl.Owner -like "O:S-1*"){$AclOwner = "**User Does Not Exist"} #Removes O:S-1 (Unidentified) owners
            else {$AclOwner = $Acl.Owner} #Owner is valid, assign it
            $Properties = [ordered]@{`
                'Folder Name' = $Folder.FullName;
                'Owner' = $AclOwner; #Reassigned from the if statement above
                'Group/User' = $Acl.Group;
                'Permissions' = 'Owner';
                'Inherited' = '';}
            $Output += New-Object -TypeName PSObject -Property $Properties
    
            #Goups/Users Permissions (Child)
            Foreach ($Access in $Acl.Access) {
                #Individual ACLs - Exluding Builtin\NTAuthority\Unidentified etc
                if(($Access.IdentityReference -like "BUILTIN*") -or`
                    ($Access.IdentityReference -like "NT AUTH*") -or`
                    ($Access.IdentityReference -like "CREATOR*") -or`
                    ($Access.IdentityReference -like "*S-1*")) {break}
                else {
                     $Properties = [ordered]@{`
                        'Folder Name' = '     -' + $Folder.FullName; #Indent this to show it belongs to the parent folder for readability 
                        'Owner' = '';
                        'Group/User' = $Access.IdentityReference;
                        'Permissions' = $Access.FileSystemRights;
                        'Inherited' = $Access.IsInherited;}
                     $Output += New-Object -TypeName PSObject -Property $Properties            
                }
            } 
        }
        Return $Output #Returns value from script block
    }   
    $newPowerShellJob = [PowerShell]::Create().AddScript($getACLCode).AddParameter('Folders',$Folders).AddParameter('x', $x)
    $getACLJob = $newPowerShellJob.BeginInvoke()
    

    #Progress Bar
    While(-Not $getACLJob.IsCompleted){
        $percentage = ($x.counter/$Folders.count*100)
        Write-Progress -Activity "Collecting Folder ACLs" -Status "Progress:" -PercentComplete $percentage
            #Estimated time left - Update every 5 seconds
            $checktimer = Get-Date; $interval = $checktimer - $updateTimer
            if($interval.Seconds -gt 2){
                $avgProgress = $x.counter/$timer.Seconds
                $remainingFolders = $FolderCount - $x.counter
                $remainingTime = [Math]::Round(($remainingFolders / $avgProgress),2)
                if($remainingTime -gt 60){$remainingTime = [Math]::Round(($remainingTime)/60,2); $timeFormat = "Minutes"}
                else{$timeFormat = "Seconds"}
                if($remainingTime -gt 60){$remainingTime = [Math]::Round(($remainingTime)/60,2); $timeFormat = "Hours"
                    if($remainingTime -gt 24){$remainingTime = [Math]::Round(($remainingTime)/24,2); $timeFormat = "Days"}}
                Clear-Host
                Write-Host "`n`n`n`n`n`nEstimate Time Remaining: $remainingTime $timeFormat"
                $updateTimer = Get-Date #Reset 1 minute timer
            }
            #Update logs every 15 minutes to show script is still running
            $checktimer = Get-Date; $timer = $checktimer - $starttimer
            if($timer.Minutes -gt 15){
                Add-Content $logs -value "$(Get-Date -Format $dtFormat)     Processing folder $x of $FoldersCount..."        
                $starttimer = Get-Date #Restart 15 minute timer      
            }
    }        
          
    #Get Job results and Clean up (GetACLJob)
    Write-Progress -Activity "Collecting ACLs..." -Completed
    $Results = $newPowerShellJob.EndInvoke($getACLJob) # Store results from job (All the ACLs)
    $newPowerShellJob.Dispose() #Clean up job    
   
    #Output results to CSV
    $Results | Export-Csv $OutFile -NoTypeInformation

    #Finished
    $end = Get-Date
    $runtime = $end - $start
    Add-Content $logs -value "$(Get-Date -Format $dtFormat)     Output file located at $OutFile"
    Add-Content $logs -value "$(Get-Date -Format $dtFormat)     Script has COMPLETED!!!"
    Add-Content $logs -value "$(Get-Date -Format $dtFormat)     Total run time: $runtime"
    Add-Content $logs -value "$(Get-Date -Format $dtFormat)     Average folders processed per second: $avgProgress"
    Write-Host "`n`nScript has completed!" -ForegroundColor Green
    Write-Host "File: "-NoNewLine 
    Write-Host $Outfile -ForegroundColor Yellow
    Write-Host "Logs: " -NoNewline
    Write-Host $logs
    Write-Host "`n`nRuntime: $runtime"
    Write-Host "`n`nAverage Folder Processed/s: $avgProgress"
}


#Start Script
#===========================
Clear-Host
if(Check-IsElevated) {Write-Host "`nPlease re-run as an " -NoNewline; Write-Host "Administrator`n`n" -ForegroundColor Yellow; exit}
Get-NTFS-ACL
