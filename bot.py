import logging
import requests
import json
import urllib3
from telegram import InlineKeyboardButton, InlineKeyboardMarkup, Update
from telegram.ext import Application, CommandHandler, CallbackQueryHandler, ContextTypes

# SSL Warning ပိတ်ခြင်း (Outline self-signed cert အတွက်)
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

# --- Configuration ---
BOT_TOKEN = '8388989661:AAG0H3zRbO27BgUDSgACmCld9c9w5g9Xu70'
OUTLINE_API_URL = 'https://31.25.236.40:44231/l31oIJVP4IDrnjjtZ5SQbg'

# --- Outline Server API Functions ---

def create_key(name):
    """Outline server မှာ key အသစ်ဆောက်ပါ"""
    try:
        response = requests.post(f"{OUTLINE_API_URL}/access-keys", verify=False)
        if response.status_code == 201:
            key_data = response.json()
            key_id = key_data['id']
            # Key နာမည်ပြောင်းမယ်
            requests.put(
                f"{OUTLINE_API_URL}/access-keys/{key_id}/name",
                data={'name': name},
                verify=False
            )
            return key_data
    except Exception as e:
        print(f"Error creating key: {e}")
    return None

def set_data_limit(key_id, limit_bytes):
    """Key အတွက် Data Limit (GB/MB) သတ်မှတ်ပါ"""
    try:
        data = {"limit": {"bytes": limit_bytes}}
        requests.put(
            f"{OUTLINE_API_URL}/access-keys/{key_id}/data-limit",
            json=data,
            verify=False
        )
        return True
    except Exception as e:
        print(f"Error setting limit: {e}")
        return False

# --- Telegram Bot Handlers ---

async def start(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """အသုံးပြုသူစဝင်လာရင် Plan တွေကို Button နဲ့ပြမယ်"""
    keyboard = [
        [
            InlineKeyboardButton("10 GB - 30 Days (Demo)", callback_data='buy_10gb_30days'),
            InlineKeyboardButton("50 GB - 30 Days (Demo)", callback_data='buy_50gb_30days'),
        ],
        [InlineKeyboardButton("Contact Admin", url='https://t.me/your_username')]
    ]
    reply_markup = InlineKeyboardMarkup(keyboard)
    await update.message.reply_text('မင်္ဂလာပါ VPN Shop မှ ကြိုဆိုပါတယ်။ Plan ရွေးချယ်ပါ။:', reply_markup=reply_markup)

async def button_click(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """Button နှိပ်လိုက်ရင် အလုပ်လုပ်မည့်အပိုင်း"""
    query = update.callback_query
    await query.answer()

    user_id = query.from_user.id
    username = query.from_user.username or f"User_{user_id}"
    
    # ရွေးချယ်လိုက်သော Plan ပေါ်မူတည်ပြီး GB သတ်မှတ်ခြင်း
    data_limit_gb = 0
    days_limit = 0
    
    if query.data == 'buy_10gb_30days':
        data_limit_gb = 10
        days_limit = 30
    elif query.data == 'buy_50gb_30days':
        data_limit_gb = 50
        days_limit = 30

    if data_limit_gb > 0:
        await query.edit_message_text(text=f"Creating {data_limit_gb}GB Key... Please wait.")
        
        # 1. Key အသစ်ဆောက်မယ်
        key_name = f"{username}_{data_limit_gb}GB"
        new_key = create_key(key_name)
        
        if new_key:
            # 2. Data Limit သတ်မှတ်မယ် (GB to Bytes)
            bytes_limit = data_limit_gb * 1024 * 1024 * 1024
            set_data_limit(new_key['id'], bytes_limit)
            
            # 3. User ဆီ Access Key ပို့မယ်
            access_url = new_key['accessUrl']
            message = (
                f"✅ **Successful!**\n\n"
                f"🔑 **Key:** `{access_url}`\n\n"
                f"📊 **Data:** {data_limit_gb} GB\n"
                f"📅 **Duration:** {days_limit} Days\n\n"
                f"Connect လုပ်ရန် Key ကို copy ကူးပြီး Outline App ထဲထည့်လိုက်ပါ။"
            )
            
            # NOTE: ဒီနေရာမှာ Database ထဲကို (key_id, created_date, expire_date) သိမ်းထားရပါမယ်။
            # နောက်ပိုင်း Expire စစ်ဖို့အတွက်ပါ။
            
            await context.bot.send_message(chat_id=user_id, text=message, parse_mode='Markdown')
        else:
            await context.bot.send_message(chat_id=user_id, text="Error creating key. Please contact admin.")

def main() -> None:
    """Bot ကို Run မည့် Main Function"""
    application = Application.builder().token(BOT_TOKEN).build()

    application.add_handler(CommandHandler("start", start))
    application.add_handler(CallbackQueryHandler(button_click))

    print("Bot is running...")
    application.run_polling()

if __name__ == "__main__":
    main()
