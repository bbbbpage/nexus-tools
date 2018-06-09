#    This program is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.

#!/bin/bash

DIR="$HOME/.nexustools"
UDEV="/etc/udev/rules.d/51-android.rules"
UDEVURL="https://raw.githubusercontent.com/M0Rf30/android-udev-rules/master/51-android.rules"
INIURL="https://raw.githubusercontent.com/apkudo/adbusbini/master/adb_usb.ini"
OS=$(uname)
ARCH=$(uname -m)
BASEURL="https://github.com/corbindavenport/nexus-tools/raw/master"
DIST=$(awk -F= '/^NAME/{print $2}' /etc/os-release)
XCODE=0

# Nexus Tools can check if a package for ADB or Fastboot is installed, and uninstall the package if needed.
_smart_remove() {
	if [ -x "$(command -v dpkg)" ]; then # Linux systems with dpkg
		PKG_OK=$(dpkg-query -W --showformat='${Status}\n' $1|grep "install ok installed")
		if [ "" == "$PKG_OK" ]; then # Check if relevant package is installed
			return 1
		else
			echo "[WARN] An outdated version of ADB or Fastboot is already installed, as part of the '$1' system package. Press ENTER to remove it or X to cancel."
			read -sn1 input
			[ "$input" = "" ] && sudo apt-get --assume-yes remove $1 && echo "[ OK ] The '$1' package was removed." || exit 1
		fi
	elif [ -x "$(command -v yum)" ]; then # Linux systems with rpm
		if [ yum list installed "$1" >/dev/null 2>&1 ]; then # Check if relevant package is installed
			return 1
		else
			echo "[WARN] An outdated version of ADB or Fastboot is already installed, as part of the '$1' system package. Press ENTER to remove it or X to cancel."
			read -sn1 input
			[ "$input" = "" ] && sudo yum -y -q remove $1 && echo "[ OK ] The '$1' package was removed." || exit 1
		fi
	fi
}

# Function for copying udex.txt to proper location
_install_udev() {
	# Install UDEV file
	if [ ! -d /etc/udev/rules.d/ ]; then
		sudo mkdir -p /etc/udev/rules.d/
	fi
	if [ -f "$UDEV" ]; then
		sudo rm "$UDEV"
	fi
	echo "[ .. ] Downloading UDEV file..."
	sudo curl -Lfk --progress-bar -o "$UDEV" "$UDEVURL"
	output=$(sudo chmod 644 $UDEV 2>&1) && echo "[ OK ] UDEV permissions fixed." || { echo "[EROR] $output"; XCODE=1; }
	output=$(sudo chown root: $UDEV 2>&1) && echo "[ OK ] UDEV ownership fixed." || { echo "[EROR] $output"; XCODE=1; }
	# Restart services
	sudo udevadm control --reload-rules 2>/dev/null >&2
	sudo service udev restart 2>/dev/null >&2
	sudo killall adb 2>/dev/null >&2
}

# Function for installing USB Vendor ID list (required for some devices to connect)
# More info: https://apkudo.com/one-true-adb_usb-ini-to-rule-them-all/
_install_ini() {
	if [ ! -d $HOME/.android/ ]; then
		mkdir -p $HOME/.android/
	fi
	if [ -f "$HOME/.android/adb_usb.ini" ]; then
		rm "$HOME/.android/adb_usb.ini"
	fi
	echo "[ .. ] Downloading ADB Vendor ID file..."
	curl -Lfk --progress-bar -o "$HOME/.android/adb_usb.ini" "$INIURL"
}

# Function for adding Nexus Tools directory to $PATH
_add_path() {
	if [ "$OS" == "Darwin" ]; then # macOS
		if [[ ":$PATH:" == *":$DIR:"* ]]; then
			# Nexus Tools directory already in $PATH
			echo "[ OK ] $DIR/ is already in PATH."
		else
			# Nexus Tools directory needs to be added to $PATH
			echo 'export PATH=$PATH:'$DIR >> ~/.bash_profile
			source $HOME/.bash_profile
			echo "[ OK ] Added $DIR/ to PATH."
		fi
	elif [ "$OS" == "Linux" ]; then # Generic Linux
		if [[ ":$PATH:" == *":$DIR:"* ]]; then
			# Nexus Tools directory already in $PATH
			echo "[ OK ] $DIR/ is already in PATH."
		else
			# Nexus Tools directory needs to be added to $PATH
			if [ -f $HOME/.bashrc ]; then
				echo 'export PATH=$PATH:'$DIR >> $HOME/.bashrc
				source $HOME/.bashrc
				echo "[ OK ] Added $DIR/ to $HOME/.bashrc."
			fi
			if [ -f $HOME/.zshrc ]; then
				echo 'export PATH=$PATH:'$DIR >> $HOME/.zshrc
				source $HOME/.zshrc
				echo "[ OK ] Added $DIR/ to $HOME/.zshrc."
			fi
		fi
	fi
}

# Function for reporting bug
_report_bug() {
	echo "[EROR] Your CPU architecture could not be detected."
	echo "[EROR] Report bugs at: github.com/corbindavenport/nexus-tools/issues"
	echo "[EROR] Report the following information in the bug report:"
	echo "[EROR] OS: $OS"
	echo "[EROR] ARCH: $ARCH"
	echo " "
}

# Start the script
echo "[INFO] Nexus Tools 4.0"
if [ "$OS" == "Linux" ]; then
	if [ "$DIST" == "Ubuntu" ] || [ "$DIST" == "Debian" ] || [ "$DIST" == "Fedora" ]; then
		echo "[ OK ] You are running Nexus Tools on a supported platform."
	else
		echo "[WARN] Nexus Tools is only tested to work on Ubuntu, Fedora, and Debian."
	fi
fi

# Check that required applications are installed
if ! [ -x "$(command -v curl)" ]; then
  echo "[EROR] The 'curl' command is not installed. Please install it and run Nexus Tools again."
  exit 1
fi
if ! [ -x "$(command -v unzip)" ]; then
  echo "[EROR] The 'unzip' command is not installed. Please install it and run Nexus Tools again."
  exit 1
fi

# Delete existing Nexus Tools installation if it exists
if [ -d $DIR ]; then
	echo "[WARN] Platform tools already installed in $DIR. Press ENTER to overwrite or X to cancel."
	read -sn1 input
	[ "$input" = "" ] && rm -rf $DIR || exit 1
fi

# Make the new directory
mkdir -p $DIR

# Check if ADB or Fastboot is already installed
if [ "$OS" == "Linux" ]; then
	# If someone wants to add support, this should work with any distro using dpkg for package management. Just change the paramteter to whatever package installs Android Platform Tools (ADB/Fastboot/etc).
	if [ "$DIST" == "Ubuntu" ] || [ "$DIST" == "Debian" ]; then
		_smart_remove "android-tools-adb"
		_smart_remove "android-tools-fastboot"
		_smart_remove "adb"
		_smart_remove "fastboot"
		_smart_remove "etc1tool"
		_smart_remove "hprof-conv"
		_smart_remove "dmtracedump"
	elif [ "$DIST" == "Fedora" ]; then
		_smart_remove "android-tools"
	fi
fi
if [ -x "$(command -v adb)" ]; then
	echo "[EROR] ADB is already installed and Nexus Tools cannot remove it automatically. Please manually uninstall ADB and try again."
	exit 1
fi
if [ -x "$(command -v fastboot)" ]; then
	echo "[EROR] Fastboot is already installed and Nexus Tools cannot remove it automatically. Please manually uninstall Fastboot and try again."
	exit 1
fi

# Detect operating system and install
if [ -d "/mnt/c/Windows" ]; then # Windows 10 Bash
	echo "[WARN] Bash on Windows 10 does not yet support USB devices. Installation will continue."
	ZIP="https://dl.google.com/android/repository/platform-tools-latest-linux.zip"
	# Download the ZIP file
	echo "[ .. ] Downloading platform tools for x86 Linux..."
	curl -Lfk --progress-bar -o "$DIR/temp.zip" "$ZIP"|| { echo "[EROR] Download failed."; XCODE=1; }
	# Unzip it
	unzip -q -o "$DIR/temp.zip" -d "$DIR"
	# Move all files from the zip to $DIR
	mv -f -v $DIR/platform-tools/* $DIR > /dev/null
	# Delete the zip file and original folder
	rm "$DIR/temp.zip"
	rmdir "$DIR/platform-tools"
	echo "[ OK ] Platform tools now installed in $DIR."
	# Add Nexus Tools directory to $PATH
	_add_path
	# Mark binaries in directory as executable
	chmod -f +x $DIR/*
	# Download Device ID list
	_install_ini
	# Download udev list
	echo "[INFO] Nexus Tools can install UDEV rules to fix potential USB issues."
	echo "[INFO] Sudo access is required. Press ENTER to proceed or X to skip."
	read -sn1 udevinput
	[ "$udevinput" = "" ] && _install_udev
elif [ "$OS" == "Darwin" ]; then # macOS
	ZIP="https://dl.google.com/android/repository/platform-tools-latest-darwin.zip"
	# Download the ZIP file
	echo "[ .. ] Downloading platform tools for macOS..."
	curl -Lfk --progress-bar -o "$DIR/temp.zip" "$ZIP"|| { echo "[EROR] Download failed."; XCODE=1; }
	# Unzip it
	unzip -q -o "$DIR/temp.zip" -d "$DIR"
	# Move all files from the zip to $DIR
	mv -f -v $DIR/platform-tools/* $DIR > /dev/null
	# Delete the zip file and original folder
	rm "$DIR/temp.zip"
	rmdir "$DIR/platform-tools"
	echo "[ OK ] Platform tools now installed in $DIR."
	# Mark binaries in directory as executable
	chmod -f +x $DIR/*
	# Download Device ID list
	_install_ini
	# Add Nexus Tools directory to $PATH
	_add_path
elif [ "$OS" == "Linux" ]; then # Generic Linux
	if [ "$ARCH" == "i386" ] || [ "$ARCH" == "i486" ] || [ "$ARCH" == "i586" ] || [ "$ARCH" == "amd64" ] || [ "$ARCH" == "x86_64" ] || [ "$ARCH" == "i686" ]; then # Linux on Intel x86/x86_64 CPU
		ZIP="https://dl.google.com/android/repository/platform-tools-latest-linux.zip"
		# Download the ZIP file
		echo "[ .. ] Downloading platform tools for x86 Linux..."
		curl -Lfk --progress-bar -o "$DIR/temp.zip" "$ZIP"|| { echo "[EROR] Download failed."; XCODE=1; }
		# Unzip it
		unzip -q -o "$DIR/temp.zip" -d "$DIR"
		# Move all files from the zip to $DIR
		mv -f -v $DIR/platform-tools/* $DIR > /dev/null
		# Delete the zip file and original folder
		rm "$DIR/temp.zip"
		rmdir "$DIR/platform-tools"
		echo "[ OK ] Platform tools now installed in $DIR."
		# Add Nexus Tools directory to $PATH
		_add_path
		# Mark binaries in directory as executable
		chmod -f +x $DIR/*
		# Download Device ID list
		_install_ini
		# Download udev list
		echo "[INFO] Nexus Tools can install UDEV rules to fix potential USB issues."
		echo "[INFO] Sudo access is required. Press ENTER to proceed or X to skip."
		read -sn1 udevinput
		[ "$udevinput" = "" ] && _install_udev
	elif [ "$ARCH" == "arm" ] || [ "$ARCH" == "armv6l" ] || [ "$ARCH" == "armv7l" ]; then # Linux on ARM CPU
		echo "[EROR] Your platform does not have up-to-date binaries available. Cannot continue with installation."
		echo " "
		exit 1
	else
		_report_bug
		exit 1
	fi
else
	_report_bug
	exit 1
fi
# All done!
if [ $XCODE -eq 0 ]; then
	echo "[INFO] Installation complete! You may need to open a new Terminal window for commands to work."
	echo "[INFO] Please consider donating to support development: bit.ly/donatenexustools"
else
	_report_bug
fi
echo " "
exit $XCODE