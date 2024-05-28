#!/bin/bash




# 設計原理
# 需要一台linux 主機 執行腳本
# Step 0 ssh 到f5 , 於/var/tmp/ 底下新增ssl 資料夾
# Step 1 將憑證跟金鑰傳送到linux 主機, 放在/var/tmp/ssl 這個路徑
# Step 2 執行'cd /var/tmp/ssl'
# Step 3 編輯腳本 執行 'vi importssl_v3.sh'
# Step 4 定義變數後存擋
# Step 5 執行腳本 './importssl_v3.sh'
# 設定變數
CERT_DIR="/var/tmp/ssl"
# F5 LTM 管理IP
F5_HOST="10.8.34.133"
# 建議使用root 帳號
F5_USER="root"
# root 密碼
F5_PASS="1q2w#E\$R"
# 憑證放置在f5 LTM的路徑
F5_SCP_PATH="/var/tmp/ssl"
# 定義要變更的網站FQDN
COMMON_NAME="www.ryantseng.work"
# 定義放在F5 LTM 的憑證與金鑰檔案名稱
RENAME_KEY="www_ryantseng_work.key"
RENAME_CER="www_ryantseng_work.cer"
# 定義舊有跟新建的Client SSL Profile
NEW_PROFILE_NAME="www_ryantseng_work"
OLD_PROFILE_NAME="www_c"
# 預計要套用的Virtual Server
APPLY_VS="vs_38_133"

# 檢查目錄是否存在
if [ ! -d "$CERT_DIR" ]; then
    echo "Error: Directory $CERT_DIR does not exist."
    exit 1
fi

# 檢查 .key 和 .cer 檔案
KEY_FILE=$(find $CERT_DIR -name "*.key")
CER_FILE=$(find $CERT_DIR -name "*.cer")

if [ -z "$KEY_FILE" ] || [ -z "$CER_FILE" ]; then
    echo "Error: .key or .cer file not found in $CERT_DIR."
    exit 1
fi

# 取得檔案的基本名稱
KEY_FILENAME=$(basename "$KEY_FILE")
CER_FILENAME=$(basename "$CER_FILE")

# 比對 .key 和 .cer 檔案是否匹配
openssl x509 -noout -modulus -in "$CERT_DIR/$CER_FILENAME" | openssl md5 > /tmp/cer_modulus
openssl rsa -noout -modulus -in "$CERT_DIR/$KEY_FILENAME" | openssl md5 > /tmp/key_modulus

if ! cmp -s /tmp/cer_modulus /tmp/key_modulus; then
    echo "Error: .key and .cer files do not match."
    exit 1
fi

# 檢查 .cer 檔案的 Common Name
CN=$(openssl x509 -in "$CERT_DIR/$CER_FILENAME" -noout -subject | grep -o "CN = [^,]*" | cut -d= -f2 | sed 's/^ *//g')

if [ "$CN" != "$COMMON_NAME" ]; then
    echo "Error: Common Name in .cer file does not match $COMMON_NAME."
    exit 1
fi

# 重新命名檔案
mv "$CERT_DIR/$KEY_FILENAME" "$CERT_DIR/$RENAME_KEY"
mv "$CERT_DIR/$CER_FILENAME" "$CERT_DIR/$RENAME_CER"

# 打印變數以供調試
echo "Key file to be transferred: $F5_SCP_PATH/$RENAME_KEY"
echo "Certificate file to be transferred: $F5_SCP_PATH/$RENAME_CER"

# SCP 傳輸檔案到 F5 設備
scp "$CERT_DIR/$RENAME_KEY" $F5_USER@$F5_HOST:$F5_SCP_PATH
if [ $? -ne 0 ]; then
    echo "Error: SCP of key file failed."
    exit 1
fi

scp "$CERT_DIR/$RENAME_CER" $F5_USER@$F5_HOST:$F5_SCP_PATH
if [ $? -ne 0 ]; then
    echo "Error: SCP of certificate file failed."
    exit 1
fi

# SSH 到 F5 設備並匯入憑證和金鑰
sshpass -p $F5_PASS ssh -T -v $F5_USER@$F5_HOST << EOF > ssh_output.log 2>&1
echo "Importing key from: $F5_SCP_PATH/$RENAME_KEY"
tmsh install sys crypto key $NEW_PROFILE_NAME from-local-file $F5_SCP_PATH/$RENAME_KEY
if [ \$? -ne 0 ]; then
    echo "Error: Importing key failed."
    exit 1
fi

echo "Importing certificate from: $F5_SCP_PATH/$RENAME_CER"
tmsh install sys crypto cert $NEW_PROFILE_NAME from-local-file $F5_SCP_PATH/$RENAME_CER
if [ \$? -ne 0 ]; then
    echo "Error: Importing certificate failed."
    exit 1
fi

echo "Creating client SSL profile: $NEW_PROFILE_NAME"
tmsh create ltm profile client-ssl $NEW_PROFILE_NAME cert $NEW_PROFILE_NAME key $NEW_PROFILE_NAME chain $NEW_PROFILE_NAME
if [ \$? -ne 0 ]; then
    echo "Error: Creating client SSL profile failed."
    exit 1
fi

echo "Modify Virtual Server profile: $APPLY_VS"
tmsh modify ltm virtual $APPLY_VS profiles add { $NEW_PROFILE_NAME } profiles delete { $OLD_PROFILE_NAME }
if [ \$? -ne 0 ]; then
    echo "Error: Modify Virtual Server ClientSSL profile failed."
    exit 1
fi


EOF

if [ $? -ne 0 ]; then
    echo "Error: SSH command execution failed. Check ssh_output.log for details."
    exit 1
fi

echo "Certificate and key have been successfully processed and imported into F5."
