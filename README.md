# Renew AnyDesk ID

รีเซ็ต AnyDesk ID ของเครื่อง Linux ให้เป็น ID ใหม่ มีไอคอนให้กดในรายการ app

ทดสอบบน Ubuntu 24.04 (GNOME) + AnyDesk 8.1.0

## ติดตั้ง

```bash
sudo apt install zenity pkexec xclip
git clone https://github.com/LEKPCSTEAM/anydesk-renew-id.git
cd anydesk-renew-id
bash install.sh          # เฉพาะ user นี้
sudo bash install.sh     # ทุก user
```

## ใช้งาน

- GUI: ค้น **"Renew AnyDesk ID"** ในรายการ app
- Terminal / SSH: `sudo anydesk-renew-id --cli`

## ถอนการติดตั้ง

```bash
bash uninstall.sh        # หรือ sudo bash uninstall.sh ถ้าติดตั้งแบบทุก user
```

## ไฟล์ที่เกี่ยวข้อง

- ไฟล์ตั้งค่าเดิมสำรองไว้ที่ `/var/backups/anydesk-renew-id/<เวลา>/`
- ประวัติการรีเซ็ต: `/var/log/anydesk-renew-id.log`

กู้ ID เดิม:

```bash
sudo systemctl stop anydesk
sudo cp -a /var/backups/anydesk-renew-id/<เวลา>/{service.conf,system.conf,.iid} /etc/anydesk/
sudo systemctl start anydesk
```

## ข้อควรระวัง

- คนที่ remote เข้าเครื่องผ่าน AnyDesk อยู่จะหลุดทันที
- รหัส Unattended Access เดิมจะหาย (โปรแกรมให้ตั้งใหม่ก่อนรีเซ็ต)
