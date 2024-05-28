# deploy_ca_to_f5
# 一個很鳥的需求，只是拿來練習寫Script

1. 當指定的資料夾裡面有憑證與金鑰檔案時, 先用openssl 比對是否為一對

2. 檢查憑證內容的CN 跟腳本指定是否一樣

3. 將憑證跟金鑰變更檔案名稱後，上傳到F5特定目錄

4. 利用sshpass ssh 下tmsh 指令 /匯入憑證/新增Client SSL profile/變更VS的profile/
   
