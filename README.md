# OCR ACL

This is a tool that can be used to automate your Chianlink OCR node's firewall to restrict traffic to known peers

---

#### I have tested this on Debian 10, and no other OS.

(use at your own risk, consider this as 100% untested)

---
## Utilization
### Create Cron Job
* You can use the included `ocr-acl-create.sh` command to be guided in generating the cron job based on the peering information in your database.  By default, the cron job will run at the top of every hour.  This is in case a peer's IP address has changed.

```bash
sudo ./ocr-acl-create.sh
```
(select option 1)

--
### Run Once
* You can run the command to manually update iptables rules, without creating a cron job.
  * If you do this, keep in mind that if a peer's IP address changes, you'll lose inbound communication with them.

```bash
sudo ./ocr-acl-create.sh
```
(select option 2)

--

### Manually Create Cron Job
* You can manually create the cron job based on the example included. You'll need to update the envrionment variables in the envVars file.
  * Most of the variables are self-explanatory; `LISTENPORT` is the value you set for `P2P_ANNOUNCE_PORT` and/or `P2P_LISTEN_PORT` in your OCR node's `.env` file
  * If yo'd prefer, you can specify the env vars in the `ocr-acl.sh` script itself, or replace them with the literal values, rather than using the `envVars` file.


## Contributing
Pull requests are welcome.

## License
[MIT](https://choosealicense.com/licenses/mit/)
