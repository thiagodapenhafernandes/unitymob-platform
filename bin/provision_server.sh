#!/bin/bash

# Configuration
SERVER_IP="143.110.138.67"
NEW_USER="salute"
KEY_PATH="$HOME/.ssh/id_ed25519.pub"

# Check if key exists
if [ ! -f "$KEY_PATH" ]; then
    echo "Error: Public key not found at $KEY_PATH"
    echo "Please generate one with: ssh-keygen -t ed25519"
    exit 1
fi

PUB_KEY=$(cat "$KEY_PATH")

echo "Connecting to $SERVER_IP as root..."
echo "You may be asked for the root password."

ssh root@$SERVER_IP <<EOF
    set -e
    
    # Detect OS and Defaults
    if [ -f /etc/debian_version ]; then
        OS="Debian"
        PKG_MGR="apt-get"
        ADMIN_GROUP="sudo"
        INSTALL_CMD="\$PKG_MGR install -y"
        UPDATE_CMD="\$PKG_MGR update"
    elif [ -f /etc/redhat-release ] || grep -E "ID=\"(centos|rhel|fedora)\"" /etc/os-release >/dev/null 2>&1; then
        OS="RedHat"
        PKG_MGR="dnf"
        ADMIN_GROUP="wheel"
        INSTALL_CMD="\$PKG_MGR install -y"
        UPDATE_CMD="\$PKG_MGR makecache"
    else
        echo "Unsupported OS or unable to detect. Defaulting to RedHat-like..."
        OS="RedHat"
        PKG_MGR="dnf"
        ADMIN_GROUP="wheel"
        INSTALL_CMD="\$PKG_MGR install -y"
        UPDATE_CMD="\$PKG_MGR makecache"
    fi
    
    # Fallback to RedHat if OS is arguably empty (CentOS 10 oddity with ssh/bash env)
    if [ -z "\$OS" ]; then
         echo "OS variable empty, forcing RedHat mode..."
         OS="RedHat"
         PKG_MGR="dnf"
    fi

    echo "Detected OS: \$OS"

    # 1. Create user if not exists
    if ! id -u $NEW_USER > /dev/null 2>&1; then
        echo "Creating user $NEW_USER..."
        useradd -m -s /bin/bash $NEW_USER
        
        # Add to admin group
        usermod -aG \$ADMIN_GROUP $NEW_USER
        
        # Configure sudoers
        echo "$NEW_USER ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/$NEW_USER
        chmod 0440 /etc/sudoers.d/$NEW_USER
    else
        echo "User $NEW_USER already exists."
    fi

    # 2. Setup SSH Key
    echo "Setting up SSH keys..."
    mkdir -p /home/$NEW_USER/.ssh
    
    # Check if key already exists to avoid duplication
    if ! grep -q "$PUB_KEY" /home/$NEW_USER/.ssh/authorized_keys 2>/dev/null; then
        echo "$PUB_KEY" >> /home/$NEW_USER/.ssh/authorized_keys
        echo "Key added."
    else
        echo "Key already authorized."
    fi
    
    chown -R $NEW_USER:$NEW_USER /home/$NEW_USER/.ssh
    chmod 700 /home/$NEW_USER/.ssh
    chmod 600 /home/$NEW_USER/.ssh/authorized_keys

    # 3. Install Basic Dependencies
    echo "Installing base dependencies..."
    \$UPDATE_CMD
    
    if [ "\$OS" = "Debian" ]; then
        \$INSTALL_CMD git curl gnupg2 build-essential libssl-dev libreadline-dev zlib1g-dev sudo autoconf automake bison libffi-dev libgdbm-dev libncurses5-dev libsqlite3-dev libtool libyaml-dev pkg-config sqlite3 libgmp-dev libreadline-dev
    elif [ "\$OS" = "RedHat" ]; then
        # Install DNF plugins core to get config-manager
        \$INSTALL_CMD dnf-plugins-core
        
        # Enable CodeReady Builder (CRB) for dev packages on CentOS/RHEL 9/10
        \$PKG_MGR config-manager --set-enabled crb || true
        
        # Install EPEL (may fail on very new versions, proceed anyway)
        \$INSTALL_CMD epel-release || true
        
        # Install dev tools group
        \$PKG_MGR groupinstall -y "Development Tools"
        
        # Install RVM specific requirements and other essentials ONE BY ONE to avoid total failure
        PACKAGES="procps-ng curl git libxcrypt-compat openssl-devel readline-devel zlib-devel libffi-devel sqlite-devel perl patch bzip2 make gcc gcc-c++ tar which"
        
        for pkg in \$PACKAGES; do
            echo "Installing \$pkg..."
            \$PKG_MGR install -y \$pkg || echo "Failed to install \$pkg (skipping)"
        done
        
        # Try libyaml-devel separately as it depends on CRB
        \$PKG_MGR install -y libyaml-devel || echo "Failed to install libyaml-devel (CRB might be off)"
    fi

    # 4. Install RVM (Multi-User) if not installed
    if ! command -v rvm > /dev/null; then
        echo "Installing RVM..."
        # Import GPG Keys
        gpg --keyserver hkp://keyserver.ubuntu.com --recv-keys 409B6B1796C275462A1703113804BB82D39DC0E3 7D2BAF1CF37B13E2069D6956105BD0E739499BDB || \
        gpg --keyserver hkp://pgp.mit.edu --recv-keys 409B6B1796C275462A1703113804BB82D39DC0E3 7D2BAF1CF37B13E2069D6956105BD0E739499BDB
        
        \curl -sSL https://get.rvm.io | bash -s stable
        usermod -a -G rvm $NEW_USER
    fi
    
    # 5. Pre-install Ruby 3.2.3 for the user
    echo "Fixing RVM permissions and preparing Homebrew..."
    
    # Ensure RVM group permissions are correct
    usermod -a -G rvm $NEW_USER
    chown -R root:rvm /usr/local/rvm
    chmod -R g+w /usr/local/rvm
    
    # Prepare Homebrew directory as root
    mkdir -p /home/linuxbrew/.linuxbrew
    chown -R $NEW_USER:$NEW_USER /home/linuxbrew
    
    # Install ALL build dependencies (as ROOT)
    echo "Installing build dependencies..."
    if [ "\$OS" = "RedHat" ]; then
        dnf install -y gcc gcc-c++ make patch bzip2 openssl-devel libyaml-devel libffi-devel readline-devel zlib-devel gdbm-devel ncurses-devel tar
    else
        apt-get install -y gcc g++ make patch bzip2 libssl-dev libyaml-dev libffi-dev libreadline-dev zlib1g-dev libgdbm-dev libncurses5-dev
    fi 
    
    # Run installation as user 'salute'
    echo "Switching to user $NEW_USER to install Homebrew and Ruby..."
    su - $NEW_USER <<INNER_EOF
        # 1. Install Homebrew (Non-Interactive)
        if [ ! -f "/home/linuxbrew/.linuxbrew/bin/brew" ]; then
            echo "Installing Linuxbrew..."
            curl -fsSL -o /tmp/install_brew.sh https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh
            chmod +x /tmp/install_brew.sh
            NONINTERACTIVE=1 /bin/bash /tmp/install_brew.sh
            rm /tmp/install_brew.sh
        fi
        
        # Add to PATH for this session
        eval "\$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
        
        # Add to .bash_profile if not already there
        if ! grep -q "brew shellenv" ~/.bash_profile 2>/dev/null; then
            echo 'eval "\$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"' >> ~/.bash_profile
        fi
        
        # 2. Install OpenSSL via Homebrew
        echo "Installing OpenSSL via Homebrew..."
        brew install openssl@3
        
        # 3. Install Ruby via RVM using Brew's OpenSSL
        source /etc/profile.d/rvm.sh
        
        # Clean up any failed attempts
        rvm remove 3.2.3 || true
        rm -rf /usr/local/rvm/src/ruby-3.2.3
        
        # Escape the command substitution so it runs on server
        OPENSSL_DIR=\$(brew --prefix openssl@3)
        echo "Installing Ruby 3.2.3 linking to OpenSSL at \$OPENSSL_DIR..."
        
        # Install with OpenSSL explicitly and disable docs
        rvm install 3.2.3 --autolibs=0 --disable-install-doc --with-openssl-dir=\$OPENSSL_DIR
        
        rvm use 3.2.3 --default
        
        echo "Installing Bundler..."
        gem install bundler
INNER_EOF
    
    echo "Done! You can now run: mina setup"
EOF
