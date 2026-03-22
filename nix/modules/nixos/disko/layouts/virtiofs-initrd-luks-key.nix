{ layout, ... }:  

{  
  # This layout uses a virtiofs mount for the initrd LUKS key  
  # Key share is mounted at /run/keys  
  # The keyFile for LUKS is set to /run/keys/luks.key  
  
  # Declare the layout attributes  
  name = "virtiofs-initrd-luks-key";  
  preOpenCommands = [  
    "mount -t virtiofs key-share /run/keys"  
  ];  
  keyFile = "/run/keys/luks.key";  
  
  # You can add other attributes and options as needed  
}