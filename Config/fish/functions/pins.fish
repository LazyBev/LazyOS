function pins --wraps='git clone https://aur.archlinux.org/paru.git && cd paru && makepkg -si' --description 'alias pins=git clone https://aur.archlinux.org/paru.git && cd paru && makepkg -si'
  git clone https://aur.archlinux.org/paru.git && cd paru && makepkg -si $argv
        
end
