# gmail_helper.py
"""
Gmail 整合模組（IMAP/SMTP 版）
─────────────────────────────
✅ 不需要 Google Cloud Console
✅ 不需要 OAuth / credentials.json
✅ 只用 Python 內建模組（imaplib / smtplib / email）
✅ 零額外安裝

【一次性設定，2 分鐘完成】
────────────────────────────────────────────────────────────
1. 用瀏覽器打開：https://myaccount.google.com/security
2. 確認「兩步驟驗證」已開啟（若未開啟，先開啟）
3. 搜尋「應用程式密碼」或直接打開：
       https://myaccount.google.com/apppasswords
4. 應用程式名稱隨便填（例如「桌面寵物」）→ 建立
5. 複製產生的 16 碼密碼（格式：xxxx xxxx xxxx xxxx）
6. 填入下方 GMAIL_ADDRESS 和 GMAIL_APP_PASSWORD
────────────────────────────────────────────────────────────
"""

from __future__ import annotations

import email
import imaplib
import re
import smtplib
import threading
from email.header import decode_header
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from typing import Dict, List, Optional, Tuple

import requests

# ─── 使用者設定（只需改這裡）─────────────────────────────

GMAIL_ADDRESS      = ""   # ← 改成你的 Gmail
GMAIL_APP_PASSWORD = ""    # ← 貼上 16 碼 App 密碼

# ─── 伺服器常數（不需更改）──────────────────────────────

IMAP_HOST = "imap.gmail.com"
IMAP_PORT = 993
SMTP_HOST = "smtp.gmail.com"
SMTP_PORT = 587

# ─── Ollama 設定 ──────────────────────────────────────────

OLLAMA_URL = "http://127.0.0.1:11434/api/chat"
MODEL_NAME = "qwen2.5:7b"

# ─── LLM 潤飾 prompt（嚴格限制只刪贅字）────────────────

EMAIL_REFINE_SYSTEM = """你是專業文字精簡助手。

【唯一任務】只刪除冗言贅字，使文字更簡潔流暢。

【嚴格禁止】
- 改變任何原意或語氣
- 新增原文未提及的任何內容
- 更換正式／非正式程度
- 補充說明或加入原文沒有的禮貌套語
- 翻譯或更改語言
- 重新組織段落結構

【輸出規則】
直接輸出修改後的郵件內容，不加任何說明、標籤或引號。"""

EMAIL_REFINE_USER = "請精簡以下郵件內容：\n\n{content}"


# ─── 主類別 ───────────────────────────────────────────────

class GmailHelper:

    def __init__(
        self,
        address:      str = GMAIL_ADDRESS,
        app_password: str = GMAIL_APP_PASSWORD,
    ):
        # 移除空格（App 密碼複製時常帶空格）
        self.address      = address.strip()
        self.app_password = app_password.replace(" ", "").strip()

    # ── 連線測試 ──────────────────────────────────────────

    def test_connection(self) -> Tuple[bool, str]:
        """測試 IMAP 連線，回傳 (success, message)"""
        try:
            with imaplib.IMAP4_SSL(IMAP_HOST, IMAP_PORT) as imap:
                imap.login(self.address, self.app_password)
            return True, "連線成功"
        except imaplib.IMAP4.error as e:
            hint = ""
            if "AUTHENTICATIONFAILED" in str(e):
                hint = (
                    "\n帳密錯誤，請確認：\n"
                    "1. GMAIL_ADDRESS 是正確的 Gmail 地址\n"
                    "2. GMAIL_APP_PASSWORD 是 16 碼 App 密碼\n"
                    "   取得：https://myaccount.google.com/apppasswords"
                )
            return False, f"IMAP 錯誤：{e}{hint}"
        except Exception as e:
            return False, f"連線失敗：{e}"

    # ── 讀取未讀郵件 ──────────────────────────────────────

    def check_new_emails(self, max_results: int = 5) -> List[Dict]:
        """
        讀取最新未讀郵件，回傳結構化清單。

        回傳欄位：uid, sender, sender_email, subject, snippet, date, body
        """
        emails: List[Dict] = []

        with imaplib.IMAP4_SSL(IMAP_HOST, IMAP_PORT) as imap:
            imap.login(self.address, self.app_password)
            imap.select("INBOX")

            status, data = imap.search(None, "UNSEEN")
            if status != "OK" or not data[0]:
                return []

            uid_list    = data[0].split()
            recent_uids = uid_list[-max_results:][::-1]   # 最新優先

            for uid in recent_uids:
                status, msg_data = imap.fetch(uid, "(RFC822)")
                if status != "OK":
                    continue

                msg          = email.message_from_bytes(msg_data[0][1])
                sender_raw   = msg.get("From", "")
                sender_name  = self._decode_str(self._parse_sender_name(sender_raw))
                sender_email = self._parse_sender_email(sender_raw)
                subject      = self._decode_str(msg.get("Subject", "（無主旨）"))
                date         = msg.get("Date", "")
                body         = self._extract_body(msg)
                snippet      = (body[:80] + "...").replace("\n", " ") if len(body) > 80 else body.replace("\n", " ")

                emails.append({
                    "uid":          uid.decode(),
                    "sender":       sender_name or sender_email,
                    "sender_email": sender_email,
                    "subject":      subject,
                    "snippet":      snippet,
                    "date":         date,
                    "body":         body,
                })

        return emails


    def check_today_unread(self, max_results: int = 20) -> Dict:
        """
        只抓「今天」的未讀郵件，回傳 count + emails。
        IMAP SINCE 搜尋格式：DD-Mon-YYYY（例如 28-Apr-2026）
        """
        from datetime import date
        today_str = date.today().strftime("%d-%b-%Y")  # e.g. "28-Apr-2026"

        emails: List[Dict] = []
        with imaplib.IMAP4_SSL(IMAP_HOST, IMAP_PORT) as imap:
            imap.login(self.address, self.app_password)
            imap.select("INBOX")

            # 搜尋今天之後的未讀
            status, data = imap.search(None, f'(UNSEEN SINCE "{today_str}")')
            if status != "OK" or not data[0]:
                return {"count": 0, "emails": []}

            uid_list    = data[0].split()
            recent_uids = uid_list[-max_results:][::-1]

            for uid in recent_uids:
                status, msg_data = imap.fetch(uid, "(RFC822)")
                if status != "OK":
                    continue
                msg          = email.message_from_bytes(msg_data[0][1])
                sender_raw   = msg.get("From", "")
                sender_name  = self._decode_str(self._parse_sender_name(sender_raw))
                sender_email = self._parse_sender_email(sender_raw)
                subject      = self._decode_str(msg.get("Subject", "（無主旨）"))
                date_str     = msg.get("Date", "")
                emails.append({
                    "uid":          uid.decode(),
                    "sender":       sender_name or sender_email,
                    "sender_email": sender_email,
                    "subject":      subject,
                    "date":         date_str,
                })

        return {"count": len(emails), "emails": emails}

    def mark_as_read(self, uid: str):
        """標記郵件為已讀"""
        with imaplib.IMAP4_SSL(IMAP_HOST, IMAP_PORT) as imap:
            imap.login(self.address, self.app_password)
            imap.select("INBOX")
            imap.store(uid.encode(), "+FLAGS", "\\Seen")

    # ── TTS 格式化（不過 LLM，直接組字串）───────────────

    def format_for_tts(self, emails: List[Dict]) -> str:
        """
        組成適合 TTS 播報的文字，完全不呼叫 LLM。

        範例：
            您有 2 封新郵件。
            第 1 封，來自 王小明，主旨是：會議通知。
            第 2 封，來自 Gmail 團隊，主旨是：安全性提醒。
        """
        if not emails:
            return "目前沒有新郵件。"
        lines = [f"您有 {len(emails)} 封新郵件。"]
        for i, e in enumerate(emails, 1):
            lines.append(
                f"第 {i} 封，來自 {e['sender']}，主旨是：{e['subject']}。"
            )
        return "\n".join(lines)

    # ── LLM 潤飾（只刪贅字，不改原意）──────────────────

    def refine_body_with_llm(self, body: str) -> Tuple[str, bool]:
        """
        用 LLM 精簡郵件內文，嚴格不改原意。
        失敗時回傳原文，was_refined=False。
        """
        if not body.strip():
            return body, False
        try:
            payload = {
                "model": MODEL_NAME,
                "messages": [
                    {"role": "system", "content": EMAIL_REFINE_SYSTEM},
                    {"role": "user",   "content": EMAIL_REFINE_USER.format(content=body)},
                ],
                "stream": False,
                "options": {"temperature": 0.1, "num_predict": 2000},
            }
            resp    = requests.post(OLLAMA_URL, json=payload, timeout=30)
            resp.raise_for_status()
            refined = resp.json().get("message", {}).get("content", "").strip()
            if not refined:
                return body, False
            print(f"[Gmail] LLM 潤飾：{len(body)} → {len(refined)} 字元")
            return refined, True
        except Exception as e:
            print(f"[Gmail] LLM 潤飾失敗，使用原文：{e}")
            return body, False

    # ── 發信：第一步 預覽 ─────────────────────────────────

    def compose_preview(
        self,
        to:     str,
        subject: str,
        body:   str,
        refine: bool = True,
    ) -> Dict:
        """
        產生郵件預覽（含 LLM 精簡），供 TTS 播報和 UI 顯示確認。

        回傳：
        {
            "to", "subject",
            "original_body",   ← 使用者原始口述
            "refined_body",    ← LLM 精簡後
            "was_refined",
            "preview_text"     ← 給 TTS / UI 的格式化文字
        }
        """
        refined_body = body
        was_refined  = False

        if refine and body.strip():
            refined_body, was_refined = self.refine_body_with_llm(body)

        preview_text = (
            f"發給：{to}\n"
            f"主旨：{subject}\n"
            f"──────────────\n"
            f"{refined_body}\n"
            f"──────────────"
        )
        return {
            "to":            to,
            "subject":       subject,
            "original_body": body,
            "refined_body":  refined_body,
            "was_refined":   was_refined,
            "preview_text":  preview_text,
        }

    # ── 發信：第二步 確認發送 ─────────────────────────────

    def send_email(self, to: str, subject: str, body: str) -> Dict:
        """
        使用者確認預覽後，呼叫此方法實際發送。

        回傳：{"success": bool, "error": str}
        """
        try:
            msg = MIMEMultipart()
            msg["From"]    = self.address
            msg["To"]      = to
            msg["Subject"] = subject
            msg.attach(MIMEText(body, "plain", "utf-8"))

            with smtplib.SMTP(SMTP_HOST, SMTP_PORT) as server:
                server.ehlo()
                server.starttls()
                server.login(self.address, self.app_password)
                server.sendmail(self.address, to, msg.as_bytes())

            print(f"[Gmail] ✅ 已發送給 {to}")
            return {"success": True, "error": ""}

        except smtplib.SMTPAuthenticationError:
            err = "SMTP 驗證失敗，請確認 App 密碼是否正確"
            print(f"[Gmail] ❌ {err}")
            return {"success": False, "error": err}
        except Exception as e:
            print(f"[Gmail] ❌ 發送失敗：{e}")
            return {"success": False, "error": str(e)}

    # ── 私有輔助 ──────────────────────────────────────────

    @staticmethod
    def _decode_str(raw: str) -> str:
        """解碼 MIME 編碼標頭（=?UTF-8?B?...?=）"""
        if not raw:
            return ""
        parts   = decode_header(raw)
        decoded = []
        for part, charset in parts:
            if isinstance(part, bytes):
                decoded.append(part.decode(charset or "utf-8", errors="ignore"))
            else:
                decoded.append(part)
        return "".join(decoded)

    @staticmethod
    def _parse_sender_name(raw: str) -> str:
        name = re.sub(r"<[^>]+>", "", raw).strip().strip('"').strip("'")
        if name:
            return name
        match = re.search(r"[\w.+-]+@", raw)
        return match.group(0).rstrip("@") if match else raw

    @staticmethod
    def _parse_sender_email(raw: str) -> str:
        match = re.search(r"<([^>]+)>", raw)
        if match:
            return match.group(1)
        if "@" in raw:
            return raw.strip()
        return ""

    @staticmethod
    def _extract_body(msg: email.message.Message) -> str:
        """從 email.message 物件提取純文字內文"""
        if msg.is_multipart():
            for part in msg.walk():
                ct = part.get_content_type()
                cd = str(part.get("Content-Disposition", ""))
                if ct == "text/plain" and "attachment" not in cd:
                    charset = part.get_content_charset() or "utf-8"
                    raw     = part.get_payload(decode=True)
                    if raw:
                        return raw.decode(charset, errors="ignore").strip()
        else:
            charset = msg.get_content_charset() or "utf-8"
            raw     = msg.get_payload(decode=True)
            if raw:
                return raw.decode(charset, errors="ignore").strip()
        return ""


# ─── 全域單例（main_api.py 直接 import 使用）─────────────

_gmail_helper: Optional[GmailHelper] = None

def get_gmail() -> GmailHelper:
    global _gmail_helper
    if _gmail_helper is None:
        _gmail_helper = GmailHelper()
    return _gmail_helper


# ─── CLI 快速測試 ─────────────────────────────────────────

if __name__ == "__main__":
    print("=" * 50)
    print(" Gmail IMAP/SMTP 測試")
    print("=" * 50)

    gmail = GmailHelper()

    ok, msg = gmail.test_connection()
    print(f"連線：{'✅' if ok else '❌'} {msg}")
    if not ok:
        exit(1)

    print("\n📬 讀取最新 3 封未讀...")
    emails = gmail.check_new_emails(max_results=3)
    print(gmail.format_for_tts(emails))

    print("\n✍️  LLM 潤飾測試：")
    test = "您好，我是想要說就是那個，關於那個明天的會議的話，我覺得我可能我就是說我會稍微晚一點點到，大概就是說會遲到個十分鐘左右，請多見諒謝謝。"
    print(f"原文：{test}")
    refined, ok = gmail.refine_body_with_llm(test)
    print(f"精簡：{refined}")