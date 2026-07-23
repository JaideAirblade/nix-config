# Windows server / SMB share management tools.
#
# Focused on the real-world workflow: copying files between network shares
# without losing NTFS permissions, and inspecting ACLs that Nautilus/gvfs
# can't display.
#
# Key tools:
#   smbclient       — CLI SMB/CIFS client (list shares, get/put, ACLs)
#   cifs-utils      — mount SMB shares with mount -t cifs (with ACL/mode options)
#   samba           — rpcclient, net, nmblookup (AD/SMB RPC operations)
#   acl             — getfacl/setfacl — view and set POSIX ACLs on mounted CIFS shares
#   pv              — pipe viewer — progress bar for large file copies
#   rsync           — preserve permissions/timestamps when copying between shares
#   pwsh            — PowerShell Core — run scripts against Windows servers (WinRM/SSH)
#
# Copying files between shares without losing permissions:
#   Method 1 (rsync):  mount both shares, rsync -aX /mnt/share1/ /mnt/share2/
#     -a = archive mode (perms, times, ownership, symlinks)
#     -X = preserve extended attributes (maps to NTFS ACLs on CIFS)
#
#   Method 2 (robocopy-style via smbclient):
#     smbclient //server/share -U user -W domain
#     > mask ""  > recurse on  > prompt off  > mget *
#     (then upload to the other share)
#
#   Method 3 (PowerShell + WinRM):
#     pwsh -c "Copy-Item -Path \\\\server1\share\* -Destination \\\\server2\share\ -Recurse -Force"
#
# Viewing NTFS permissions on a mounted CIFS share:
#   getfacl /mnt/share/folder          # show ACLs in POSIX format
#   smbcacls //server/share folder -U user  # show NTFS ACLs directly via SMB
#
# Mounting a share with ACL support:
#   sudo mount -t cifs //server/share /mnt/share \
#     -o username=user,domain=DOMAIN,uid=$(id -u),gid=$(id -g),\
#     cifsacl,mode=0770,file_mode=0770,dir_mode=0770
#
# The `cifsacl` option maps NTFS ACLs to POSIX ACLs so getfacl/setfacl work.
{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    # --- SMB/CIFS core ---
    samba            # smbclient, rpcclient, net, nmblookup, smbcacls
    cifs-utils       # mount.cifs, cifs.idmap — mount SMB shares with ACL support

    # --- ACL inspection & manipulation ---
    acl              # getfacl, setfacl — view/set POSIX ACLs on mounted CIFS shares

    # --- File copy with permission preservation ---
    rsync            # -aX preserves permissions + extended attributes (NTFS ACLs)
    pv               # progress bars for large copies (pv < file > /mnt/share/file)

    # --- PowerShell Core ---
    powershell       # pwsh — run .ps1 scripts, WinRM sessions, AD cmdlets

    # --- AD / Windows admin ---
    evil-winrm       # WinRM shell for Windows servers (Ruby-based)
    (python312.withPackages (ps: with ps; [
      impacket       # Python AD toolkit: psexec.py, wmiexec.py, secretsdump.py
    ]))
    netexec          # Network execution — enumerate shares/users/sessions at scale
  ];
}