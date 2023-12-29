"use strict";

const TelegramBot = require('node-telegram-bot-api');
const service = require('./service.js');

const RUN_TIMEOUT = 500;
const JOB_TIMEOUT = 60000;

let bot = null;
let commands = [];
let isProcessing = false;

async function sendCallback(chatId, text, reply) {
    let r = null;
    if (chatId) {
        try {
          if (reply) {
            r = await bot.sendMessage(chatId, text, {
              reply_to_message_id: reply
            });
          } else {
            r = await bot.sendMessage(chatId, text);
          }
        } catch (error) {
          console.error(error);
        }
    }
    return r;
}

async function menuCallback(chatId, text, msg) {
    let r = null;
    if (chatId) {
      try {
        r = await bot.sendMessage(chatId, text, msg);
      } catch (error) {
        console.error(error);
      }
    }
    return r;
}

async function deleteMessage(chatId, msgId) {
    if (chatId && msgId) {
        try {
          await bot.deleteMessage(chatId, msgId);
        } catch (error) {
          console.error(error);
        }
    }
}

async function job() {
    let r = false;
    if (isProcessing) return false;
    isProcessing = true;
    r = await service.runJob();
    isProcessing = false;
    return r;
}

async function exec() {
    if (isProcessing) return false;
    isProcessing = true;
    let r = false;
    if (await service.getActions()) r = true;
    if (await service.getMenu(menuCallback)) r = true;
    if (await service.getVirtualMenu(menuCallback)) r = true;
    if (await service.getParams(sendCallback)) r = true;
    if (await service.setParams()) r = true;
    if (await service.sendInfo(sendCallback)) r = true;
    if (await service.sendMessages(sendCallback)) r = true;
    if (await service.httpRequest()) r = true;
    if (await service.dbProc()) r = true;
    isProcessing = false;
    return r;
}

let run = async function() {
    if (await exec()) {
        setTimeout(run, RUN_TIMEOUT);
    }
}
  
let schedule = async function() {
    if (await job()) {
        await run();
    }
    setTimeout(schedule, JOB_TIMEOUT);
}
    

const init = async function() {
    if (bot === null) {
        const token = await service.getToken();
        bot = new TelegramBot(token, { polling: true });
        bot.on('text', async msg => {
//          console.log(msg);
            try {
                const chatId = msg.chat.id;
                commands = await service.getCommands();
                let menu = [];
                for (let i = 0; i < commands.length; i++) {
                    menu.push({
                      command: commands[i].name,
                      description: commands[i].descr
                    });
                }
                if (menu.length > 0) {
                    bot.setMyCommands(menu);
                }
                let cmd = null;
                const r = msg.text.match(/\/(\w+)\s*(\S+)*/);
                if (r) {
                    cmd = r[1];
                }
                if (cmd !== null) {
                    if (cmd == 'start') {
                      await service.createUser(msg.from.username ? msg.from.username : msg.from.id, msg.from.id, chatId, msg.from.first_name, msg.from.last_name, msg.from.language_code);
                      await run();
                      return;
                    }
                }
                if (await service.saveParam(msg.from.username ? msg.from.username : msg.from.id, msg.text, chatId, msg.message_id, deleteMessage)) {
                    await run();
                    return;
                }
                if (cmd !== null) {
                    for (let i = 0; i < commands.length; i++) {
                        if (commands[i].name == cmd) {
                            let params = [];
                            for (let j = 0; j < commands[i].params.length; j++) {
                                if (r[j + 2]) {
                                    params.push({
                                        id: commands[i].params[j],
                                        value: r[j + 2]
                                    });
                                }
                            }
                            await service.addAction(msg.from.username ? msg.from.username : msg.from.id, commands[i].action, params);
                            await run();
                            return;
                        }
                    }
                }
                await service.saveMessage(msg.from.username ? msg.from.username : msg.from.id, msg.message_id, msg.text, msg.reply_to_message);
            } catch (error) {
                console.error(error);
            }
        });
        bot.on('callback_query', async msg => {
//              console.log(msg);
                try {
                  const chatId = msg.from.id;
                  await service.chooseItem(msg.from.username ? msg.from.username : msg.from.id, msg.data, chatId, deleteMessage);
                  await run();
                } catch (error) {
                  console.error(error);
                }
        });
    }
    await run();
    await schedule();
}
  
init();