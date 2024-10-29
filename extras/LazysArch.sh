#!/bin/bash

set -eau

# Function to prompt for user input with a default value
prompt() {
    local prompt_text="$1"
    local default_value="$2"
    read -p "$prompt_text [$default_value]: " input
    echo "${input:-$default_value}"
}

# Ask for user input
disk=$(prompt "Enter the disk to install Arch Linux (e.g., /dev/sda)" "/dev/sda")
hostname=$(prompt "Enter the hostname (default: archlinux)" "archlinux")
user=$(prompt "Enter the username (default: user)" "user")
password=$(prompt "Enter the password (default: password124)" "password124")
locale=$(prompt "Enter the locale (default: en_GB.UTF-8)" "en_GB.UTF-8")
timezone=$(prompt "Enter the timezone (default: Europe/London)" "Europe/London")

# Prompt for partition sizes
boot_size=$(prompt "Enter the size for the boot partition (e.g., 512M)" "512M")
root_size=$(prompt "Enter the size for the root partition (e.g., 20G)" "20G")

# GPU Driver selection
gpu_driver=$(prompt "Enter GPU driver (options: nvidia, amd, intel, open-source):" "nvidia")

# CPU Microcode selection
cpu_ucode=$(prompt "Enter CPU microcode (options: amd-ucode, intel-ucode):" "amd-ucode")

# Confirm disk operations
read -p "Are you sure you want to proceed with partitioning $disk? (y/n) " confirm
[[ "$confirm" != "y" ]] && exit 1

# Determine disk prefix
if [[ "$disk" == /dev/nvme* ]]; then
    disk_prefix="p"
else
    disk_prefix=""
fi

# Partition the disk
(
echo o # Create a new empty GPT partition table
echo n # New partition for boot
echo p # Primary
echo 1 # Partition number
echo   # First sector (Accept default: will start at the beginning of the disk)
echo +"$boot_size" # Size of the boot partition
echo n # New partition for root
echo p # Primary
echo 2 # Partition number
echo   # First sector (Accept default)
echo +"$root_size" # Size of the root partition
echo n # New partition for swap or additional partitions if required
echo p # Primary
echo 3 # Partition number
echo   # First sector (Accept default)
echo   # Last sector (Accept default: will use remaining space)
echo w # Write the partition table
) | fdisk "$disk"

# Format the partitions
mkfs.fat -F32 "$disk$disk_prefix"1 || { echo "Failed to format boot partition" && exit 1; }
mkfs.ext4 "$disk$disk_prefix"2 || { echo "Failed to format root partition" && exit 1; }

# Mount the filesystems
mount "$disk$disk_prefix"2 /mnt
mkdir /mnt/boot
mount "$disk$disk_prefix"1 /mnt/boot

# Swap
mkswap "$disk$disk_prefix"3 || { echo "Failed to format swap partition" && exit 1; }
swapon "$disk$disk_prefix"3 || { echo "Failed to enable swap partition" && exit 1; }

# Install the base system
pacstrap /mnt base linux linux-firmware vim

# Generate fstab
genfstab -U /mnt >> /mnt/etc/fstab

# Chroot into the new system
arch-chroot /mnt /bin/bash <<EOF
# Set timezone
ln -sf /usr/share/zoneinfo/$timezone /etc/localtime
hwclock --systohc

# Localization
echo "$locale UTF-8" > /etc/locale.gen
locale-gen
echo "LANG=$locale" > /etc/locale.conf

# Hostname
echo "$hostname" > /etc/hostname

# Set root password
echo "root:$password" | chpasswd

# Create a new user
useradd -m -G wheel "$user"
echo "$user:$password" | chpasswd

# Enable sudo for wheel group
echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers

# Pacman.conf
sed -i '/Color/s/^#//g' /etc/pacman.conf
sed -i '/ParallelDownloads/s/^#//g' /etc/pacman.conf
sed -i '/#\[multilib\]/s/^#//' /etc/pacman.conf
sed -i '/#Include = \/etc\/pacman\.d\/mirrorlist/s/^#//' /etc/pacman.conf

# Install necessary packages based on selections
pacman -Syu --noconfirm grub efibootmgr systemd i3 gcc $cpu_ucode networkmanager network-manager-applet

# GPU Driver installation
case "$gpu_driver" in
    nvidia)
        pacman -S --noconfirm xf86-video-nouveau nvidia nvidia-dkms nvidia-utils mesa
        ;;
    amd)
        pacman -S --noconfirm xf86-video-amdgpu mesa
        ;;
    intel)
        pacman -S --noconfirm xf86-video-intel mesa
        ;;
    open-source)
        pacman -S --noconfirm mesa
        ;;
    *)
        echo "Unknown GPU driver choice, skipping GPU driver installation."
        ;;
esac

# GRUB Bootloader installation
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

# Network Manager setup
systemctl disable dhcpcd
systemctl stop dhcpcd
systemctl enable NetworkManager
systemctl start NetworkManager

# Setting up LazyOS
git clone https://aur.archlinux.org/yay-bin.git
sudo chown "$user:$user" -R yay-bin && cd yay-bin 
makepkg -si && cd ..

yay -S steam wine firefox flatpak bluez bluez-utils i3 git github-cli nmap wireshark-qt amd-ucode neovim vim john hydra aircrack-ng sqlmap hashcat nikto openbsd-netcat metasploit amd_ucode kitty systemd base xdg-desktop-portal xdg-desktop-portal-gtk base-devel efibootmgr sof-firmware mesa nvidia-prime systemd linux linux-headers linux-firmware networkmanager network-manager-applet wireless_tools neofetch gvfs pavucontrol polkit-gnome lxappearance bottom fcitx5-im fcitx5-mozc adobe-source-han-sans-jp-fonts adobe-source-han-serif-jp-fonts adobe-source-han-sans-kr-fonts adobe-source-han-serif-kr-fonts adobe-source-han-sans-cn-fonts adobe-source-han-serif-cn-fonts nano rofi curl make cmake meson obsidian man-db xdotool thunar nitrogen flameshot zip unzip mpv btop emacs noto-fonts picom wireplumber dunst xarchiver eza thunar-archive-plugin
flatpak install --user https://sober.vinegarhq.org/sober.flatpakref

sudo systemctl enable bluetooth.service
sudo systemctl start bluetooth.service
lsusb | grep -i bluetooth
sudo systemctl daemon-reload

# My config
echo "---- Making backup at $HOME/configBackup -----"
sudo cp -rpf "$HOME/.config" "$HOME/configBackup"
echo "----- Backup made at $HOME/configBackup ------"

# Copy configurations
for config in dunst fcitx5 mozc fish i3 nvim rofi omf; do
    sudo cp -rpf "$HOME/LazysArch/$config" "$HOME/.config/";
done

for fonts in fonts/MartianMono fonts/SF-Mono-Powerline fonts/fontconfig; do
    sudo cp -rpf "$HOME/LazysArch/$fonts" "$HOME/.local/share/fonts/";
done

mkdir -p "$HOME/.config/neofetch/" && sudo cp --parents -rpf "$HOME/LazysArch/neofetch/bk" "$HOME/.config/neofetch/"
mkdir -p "$HOME/Pictures/" && sudo cp -rpf "$HOME/LazysArch/Pictures/bgpic.jpg" "$HOME/Pictures/"
sudo cp -rpf "$HOME/LazysArch/Misc/picom.conf" "$HOME/.config/"
mkdir -p "$HOME/Videos"

~/.config/emacs/bin/doom install
~/.config/emacs/bin/doom sync

# Install the necessary packages
prop=""
NVIDIA_VENDOR="0x10de"

# Check available graphics providers and OpenGL renderer
xrandr --listproviders && glxinfo | grep "OpenGL renderer"

# Set up the offloading sink for hybrid graphics (replace radeon if necessary)
echo "Setting offloading sink..."
read -p "Enter the provider number for offloading sink (e.g., 1): " provider_number
xrandr --setprovideroffloadsink $provider_number

# Check OpenGL renderer for PRIME offloading and GPU power state
DRI_PRIME=1 glxinfo | grep "OpenGL renderer"
cat /sys/class/drm/card*/device/power_state

# Create udev rules for NVIDIA power management
echo "Creating udev rules for NVIDIA power management..."
sudo tee /etc/udev/rules.d/80-nvidia-pm.rules > /dev/null <<EOL
# Enable runtime PM for NVIDIA VGA/3D controller devices on driver bind
ACTION=="bind", SUBSYSTEM=="pci", ATTR{vendor}=="$NVIDIA_VENDOR", ATTR{class}=="0x030000", TEST=="power/control", ATTR{power/control}="auto"
ACTION=="bind", SUBSYSTEM=="pci", ATTR{vendor}=="$NVIDIA_VENDOR", ATTR{class}=="0x030200", TEST=="power/control", ATTR{power/control}="auto"

# Disable runtime PM for NVIDIA VGA/3D controller devices on driver unbind
ACTION=="unbind", SUBSYSTEM=="pci", ATTR{vendor}=="$NVIDIA_VENDOR", ATTR{class}=="0x030000", TEST=="power/control", ATTR{power/control}="on"
ACTION=="unbind", SUBSYSTEM=="pci", ATTR{vendor}=="$NVIDIA_VENDOR", ATTR{class}=="0x030200", TEST=="power/control", ATTR{power/control}="on"

# Enable runtime PM for NVIDIA VGA/3D controller devices on adding device
ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="$NVIDIA_VENDOR", ATTR{class}=="0x030000", TEST=="power/control", ATTR{power/control}="auto"
ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="$NVIDIA_VENDOR", ATTR{class}=="0x030200", TEST=="power/control", ATTR{power/control}="auto"
EOL

# Configure NVIDIA Dynamic Power Management
echo "Configuring NVIDIA Dynamic Power Management..."
sudo tee /etc/modprobe.d/nvidia-pm.conf > /dev/null <<EOL
options nvidia NVreg_DynamicPowerManagement=0x02
EOL

# Check runtime power management status and suspended time for the NVIDIA device
echo "Checking NVIDIA power management status..."
cat /sys/bus/pci/devices/0000:01:00.0/power/runtime_status
cat /sys/bus/pci/devices/0000:01:00.0/power/runtime_suspended_time

# Start and enable the NVIDIA persistence daemon
echo "Starting and enabling NVIDIA persistence daemon..."
sudo systemctl start nvidia-persistenced.service
sudo systemctl enable nvidia-persistenced.service

yay -S fish

curl https://raw.githubusercontent.com/oh-my-fish/oh-my-fish/master/bin/install | fish
chsh -s /usr/bin/fish

EOF

# Unmount the partitions
umount -R /mnt

echo "Installation complete. Reboot your system."
