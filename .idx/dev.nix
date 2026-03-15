{ pkgs, ... }: {
  channel = "stable-24.11";

  packages = [
    pkgs.qemu
    pkgs.htop
    pkgs.cloudflared
    pkgs.coreutils
    pkgs.gnugrep
    pkgs.wget
    pkgs.git
    pkgs.python3
  ];

  idx.workspace.onStart = {
    qemu = ''
      set -e

      # 1. Dọn dẹp workspace cũ
      if [ ! -f /home/user/.cleanup_done ]; then
        echo "Cleaning up..."
        rm -rf /home/user/.gradle/* /home/user/.emu/* || true
        find /home/user -mindepth 1 -maxdepth 1 \
          ! -name 'test' \
          ! -name '.cleanup_done' \
          ! -name '.*' \
          -exec rm -rf {} + || true
        touch /home/user/.cleanup_done
      fi

      # 2. Cấu hình đường dẫn
      SKIP_QCOW2_DOWNLOAD=1 
      VM_DIR="$HOME/qemu"
      RAW_DISK="$VM_DIR/windows.qcow2"
      WIN_ISO="$VM_DIR/automic11.iso"
      VIRTIO_ISO="$VM_DIR/virtio-win.iso"
      NOVNC_DIR="$HOME/noVNC"
      OVMF_DIR="$HOME/qemu/ovmf"
      OVMF_CODE="$OVMF_DIR/OVMF_CODE.fd"
      OVMF_VARS="$OVMF_DIR/OVMF_VARS.fd"

      mkdir -p "$OVMF_DIR" "$VM_DIR"

      # 3. Tải Firmware & Driver
      if [ ! -f "$OVMF_CODE" ]; then
        wget -O "$OVMF_CODE" https://qemu.weilnetz.de/test/ovmf/usr/share/OVMF/OVMF_CODE.fd
      fi
      if [ ! -f "$OVMF_VARS" ]; then
        wget -O "$OVMF_VARS" https://qemu.weilnetz.de/test/ovmf/usr/share/OVMF/OVMF_VARS.fd
      fi

      # 4. Tạo ổ cứng 1TB (Flex Mode)
      if [ ! -f "$RAW_DISK" ]; then
        echo "Creating 1TB QCOW2 disk..."
        qemu-img create -f qcow2 "$RAW_DISK" 1T
      fi

      # 5. Tải ISO Windows
      if [ ! -f "$WIN_ISO" ]; then
        wget -O "$WIN_ISO" https://github.com/kmille36/idx-windows-gui/releases/download/1.0/automic11.iso
      fi
      if [ ! -f "$VIRTIO_ISO" ]; then
        wget -O "$VIRTIO_ISO" https://github.com/kmille36/idx-windows-gui/releases/download/1.0/virtio-win-0.1.271.iso
      fi

      # 6. Cài đặt noVNC
      if [ ! -d "$NOVNC_DIR/.git" ]; then
        git clone https://github.com/novnc/noVNC.git "$NOVNC_DIR"
      fi

      # 7. Khởi chạy QEMU (12 Cores / 28GB RAM)
      echo "Starting QEMU..."
      nohup qemu-system-x86_64 \
        -enable-kvm \
        -cpu host,+topoext,hv_relaxed,hv_spinlocks=0x1fff,hv-passthrough,kvm=on \
        -smp 12,cores=12 \
        -M q35,usb=on \
        -device usb-tablet \
        -m 28672 \
        -device virtio-balloon-pci \
        -vga virtio \
        -net nic,netdev=n0,model=virtio-net-pci \
        -netdev user,id=n0,hostfwd=tcp::3389-:3389 \
        -boot d \
        -drive if=pflash,format=raw,readonly=on,file="$OVMF_CODE" \
        -drive if=pflash,format=raw,file="$OVMF_VARS" \
        -drive file="$RAW_DISK",format=qcow2,if=virtio \
        -cdrom "$WIN_ISO" \
        -drive file="$VIRTIO_ISO",media=cdrom,if=ide \
        -vnc :0 \
        -display none > /tmp/qemu.log 2>&1 &

      # 8. Chạy Tunnel & In URL
      nohup "$NOVNC_DIR/utils/novnc_proxy" --vnc 127.0.0.1:5900 --listen 8888 > /tmp/novnc.log 2>&1 &
      nohup cloudflared tunnel --no-autoupdate --url http://localhost:8888 > /tmp/cloudflared.log 2>&1 &

      sleep 10
      if grep -q "trycloudflare.com" /tmp/cloudflared.log; then
        URL=$(grep -o "https://[a-z0-9.-]*trycloudflare.com" /tmp/cloudflared.log | head -n1)
        echo "========================================="
        echo " 🌍 Win 11 (12 C / 1T) Ready:"
        echo "     $URL/vnc.html"
        mkdir -p /home/user/test
        echo "$URL/vnc.html" > /home/user/test/noVNC-url.txt
        echo "========================================="
      fi

      # Giữ workspace hoạt động
      elapsed=0
      while true; do
        echo "Time elapsed: $elapsed min"
        ((elapsed++))
        sleep 60
      done
    '';
  };

  idx.previews = {
    enable = true;
    previews = {
      qemu = {
        manager = "web";
        command = [ "bash" "-lc" "echo 'noVNC running on port 8888'" ];
      };
    };
  };
}
