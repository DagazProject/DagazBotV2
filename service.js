"use strict";

const db = require('./database.js');
const axios = require('axios');

const BOT_DEVICE = 'telegram';

async function getToken() {
    try {
      const x = await db.query(
        `select token, id from server_token order by id limit 1`);
      return x.rows[0].token;
    } catch (error) {
      console.error(error);
    }
}

async function getCommands() {
    try {
      let r = [];
      const x = await db.query(
        `select command, action_id, script_id, name from command_list`);
         if (x.rows && x.rows.length > 0) {
             for (let i = 0; i < x.rows.length; i++) {
                 let p = [];
                 const y = await db.query(
                  `select a.paramtype_id from script_param a where a.script_id = $1 order by a.order_num`, [x.rows[i].script_id]);
                 if (y.rows && y.rows.length > 0) {
                     for (let j = 0; j < y.rows.length; j++) {
                          p.push(y.rows[j].paramtype_id);
                     }
                 }
                 r.push({
                    name: x.rows[i].command,
                    descr: x.rows[i].name,
                    action: x.rows[i].action_id,
                    params: p
                });
             }
         }
      return r;
    } catch (error) {
      console.error(error);
    }
  }

  async function getUserId(username) {
    const x = await db.query(
      `select id from users a where a.username = $1`, [username]);
    if (!x.rows || x.rows.length == 0) {
       return null;
    }
    return x.rows[0].id;
  }

  async function getContextId(username) {
    const x = await db.query(
      `select context_id from users a where a.username = $1`, [username]);
    if (!x.rows || x.rows.length == 0) {
       return null;
    }
    return x.rows[0].context_id;
  }

  async function addAction(username, action, params) {
    try {
      const id = await getContextId(username);
      await db.query(`select clearActivity($1)`, [id]);
      const x = await db.query(`select addCommand($1, $2) as id`, [id, action]);
      if (!x.rows || x.rows.length == 0) return;
      for (let i = 0; i < params.length; i++) {
        await db.query(`insert into command_param(command_id, paramtype_id, value) values ($1, $2, $3)`, [x.rows[0].id, params[i].id, params[i].value]);
      }
    } catch (error) {
      console.error(error);
    }
  }

  async function createUser(login, user, chat, first_name, last_name, locale) {
    try {
      await db.query(`select createUser($1, $2, $3, $4, $5, $6)`, [login, user, chat, first_name, last_name, locale]);
    } catch (error) {
      console.error(error);
    }
  }

  async function getActions() {
    try {
      const x = await db.query(`select getCommands() as n`);
      if (!x.rows || x.rows.length == 0 || x.rows[0].n) return false;
      return true;
    } catch (error) {
      console.error(error);
    }
  }

  async function getVirtualMenu(menucallback) {
    try {
      const x = await db.query(
        `select user_id, id, chat_id, message, value, context_id, width, scheduled from virtual_menu order by scheduled limit 100`);
      if (!x.rows || x.rows.length == 0) return false;
      for (let i = 0; i < x.rows.length; i++) {
        const list = x.rows[i].value.split(/,/);
        let menu = []; let row = [];
        for (let j = 0; j < list.length; j++) {
            if (row.length >= x.rows[i].width) {
               menu.push(row);
               row = [];
            }
            row.push({
              text: list[j],
              callback_data: list[j]
            });
         }
         if (row.length > 0) {
            menu.push(row);
         }
         let msg = null;
         if (menu.length > 0) {
           msg = await menucallback(x.rows[i].chat_id, x.rows[i].message, {
             reply_markup: {
               inline_keyboard: menu
             }
          });
        }
        await db.query(`update common_context set delete_message = $1, scheduled = null where id = $2`, [msg.message_id, x.rows[i].context_id]);
     }
     return true;
  } catch (error) {
      console.error(error);
    }
  }

  async function getMenu(menucallback) {
    try {
      const x = await db.query(
        `select user_id, id, chat_id, message, locale, context_id, width from static_menu order by scheduled limit 100`);
      if (!x.rows || x.rows.length == 0) return false;
      for (let i = 0; i < x.rows.length; i++) {
        const y = await db.query(
       `select a.id, a.order_num, c.message from action a inner join localized_string c on (c.action_id = a.id and c.locale = $1) where a.parent_id = $2 order by a.order_num`, [x.rows[i].locale, x.rows[i].id]);
        let menu = []; let row = [];
        for (let j = 0; j < y.rows.length; j++) {
            if (row.length >= x.rows[i].width) {
                menu.push(row);
                row = [];
            }
            row.push({
              text: y.rows[j].message,
              callback_data: y.rows[j].id
            });
        }
        if (row.length > 0) {
          menu.push(row);
        }
        let msg = null;
        if (menu.length > 0) {
           msg = await menucallback(x.rows[i].chat_id, x.rows[i].message, {
             reply_markup: {
               inline_keyboard: menu
             }
          });
        }
        await db.query(`update common_context set delete_message = $1, action_id = null, scheduled = null where id = $2`, [msg.message_id, x.rows[i].context_id]);
     }
     return true;
   } catch (error) {
      console.error(error);
    }
  }

  async function chooseItem(username, data, chatId, del) {
    try {
      const x = await db.query(
        `select id, paramtype_id, follow_to, delete_message, context_id from user_action where username = $1`, [username]);
      if (!x.rows || x.rows.length == 0) return;
      let action = x.rows[0].follow_to;
      if (x.rows[0].paramtype_id) {
        await db.query(`update user_param set created = now(), value = $1 where user_id = $2 and type_id = $3`, [data, x.rows[0].id, x.rows[0].paramtype_id]);
      } else {
        const y = await db.query(
          `select x.id from (select a.id, row_number() over (order by a.order_num) as rn from action a where a.parent_id = $1) x where  x.rn = 1`, [data]);
        if (y.rows && y.rows.length > 0) {
           action = y.rows[0].id;
        }
      }
      if (x.rows[0].delete_message) {
        del(chatId, x.rows[0].delete_message);
      }
      await db.query(`update common_context set delete_message = null, action_id = $1, scheduled = $2 where id = $3`, [action, action ? new Date() : null, x.rows[0].context_id]);
    } catch (error) {
      console.error(error);
    }
  }

  async function getNextAction(id, isParent) {
    const x = await db.query(
      `select a.script_id, coalesce(a.parent_id, 0) as parent_id, a.order_num from action a where a.id = $1`, [id]);
    if (!x.rows || x.rows.length == 0) return null;
    if (isParent) {
      const z = await db.query(
        `select a.id from action a where a.script_id = $1 and coalesce(a.parent_id, 0) = $2 order by a.order_num`, [x.rows[0].script_id, id]);
      if (z.rows && z.rows.length > 0) return z.rows[0].id;
    }
    const y = await db.query(
      `select a.id from action a where a.script_id = $1 and coalesce(a.parent_id, 0) = $2 and a.order_num > $3 order by a.order_num`, [x.rows[0].script_id, x.rows[0].parent_id, x.rows[0].order_num]);
    if (!y.rows || y.rows.length == 0) return null;
    return y.rows[0].id;
  }

  async function setParams() {
    try {
      const x = await db.query(`select setParams() as n`);
      if (!x.rows || x.rows.length == 0 || x.rows[0].n == 0) return false;
      return true;
  } catch (error) {
      console.error(error);
    }
  }

  async function replacePatterns(user_id, s) {
    let r = s.match(/{(\S+)}/);
    while (r) {
      const name = r[1];
      const x = await db.query(
        `select b.value from param_type a left join user_param b on (b.type_id = a.id and b.user_id = $1) where  a.name = $2`, [user_id, name]);
      let v = '';
      if (x.rows && x.rows.length > 0) v = x.rows[0].value;
      s = s.replace('{' + name + '}', v);
      r = s.match(/{(\S+)}/);
    }
    return s;
  }

  async function sendInfo(send) {
    try {
      const x = await db.query(
        `select chat_id, id, message, follow_to, user_id, data, context_id from info_list order by scheduled limit 100`);
      if (!x.rows || x.rows.length == 0) return false;
      for (let i = 0; i < x.rows.length; i++) {
        let message = x.rows[i].message;
        message = await replacePatterns(x.rows[i].user_id, message);
        await send(x.rows[i].chat_id, message);
        let action = x.rows[i].follow_to;
        if (!action) {
            action = await getNextAction(x.rows[i].id, false);
        }
        await db.query(`update common_context set action_id = $1, scheduled = $2 where id = $3`, [action, action ? new Date() : null, x.rows[i].context_id]);
      }
      return true;
    } catch (error) {
      console.error(error);
    }
  }

  async function getParams(send) {
    try {
      const x = await db.query(
        `select chat_id, id, paramtype_id, message, context_id from param_list order by scheduled limit 100`);
      if (!x.rows || x.rows.length == 0) return false;
      for (let i = 0; i < x.rows.length; i++) {
        let message = x.rows[i].message;
        message = await replacePatterns(x.rows[i].id, message);
        await send(x.rows[i].chat_id, message);
        await db.query(`update common_context set scheduled = null, wait_for = $1 where id = $2`, [x.rows[i].paramtype_id, x.rows[i].context_id]);
     }
     return true;
   } catch (error) {
      console.error(error);
    }
  }

  async function saveParam(username, data, chatId, msgId, del) {
    try {
      const x = await db.query(
        `select user_id, wait_for, id, action_id, is_hidden, context_id from param_action where username = $1`, [username]);
      if (!x.rows || x.rows.length == 0) return false;
      const action = await getNextAction(x.rows[0].action_id, true);
      await db.query(`select setParamValue($1, $2, $3)`, [x.rows[0].user_id, x.rows[0].wait_for, data]);
      if (x.rows[0].is_hidden) {
        await del(chatId, msgId);
      }
      await db.query(`update common_context set action_id = $1, scheduled = $2, wait_for = null where id = $3`, [action, action ? new Date() : null, x.rows[0].context_id]);
      return true;
    } catch (error) {
      console.error(error);
    }
  }

  async function saveMessage(username, id, data, reply) {
    try {
      if (data.length > 1024) return;
      let reply_id = null;
      if (reply) {
          const x = await db.query(
            `select b.message_id from client_message a inner join message b on (b.id = a.parent_id) where a.message_id = $1`, [reply.message_id]);
          if (x.rows && x.rows.length > 0) {
             reply_id = x.rows[0].message_id;
          }
        }
      await db.query(`select saveMessage($1, $2, $3, $4)`, [username, id, data, reply_id]);
    } catch (error) {
      console.error(error);
    }
  }

  async function sendMessages(send) {
    try {
      const x = await db.query(
        `select id, send_to, locale, data, is_admin, reply_for from message_list order by scheduled limit 1`);
      if (!x.rows || x.rows.length == 0) return false;
      if (x.rows[0].send_to) {
        const y = await db.query(
          `select a.chat_id, b.id from users a left join message b on (b.user_id = a.id and b.message_id = $1) where a.id = $2`, [x.rows[0].reply_for, x.rows[0].send_to]);
           if (y.rows && y.rows.length > 0 && (!x.rows[0].reply_for || y.rows[0].id)) {
             const msg = await send(y.rows[0].chat_id, x.rows[0].data, x.rows[0].reply_for);
             if (msg) {
                await db.query(`insert into client_message(parent_id, message_id) values ($1, $2)`, [x.rows[0].id, msg.message_id]);
             }
           }
      } else {
        if (x.rows[0].is_admin) {
            const y = await db.query(
              `select a.chat_id, c.id from users a left join user_param b on (b.user_id = a.id and type_id = 7) left join message c on (c.user_id = a.id and c.message_id = $1) where coalesce(b.value, 'en') = $2`, [x.rows[0].reply_for, x.rows[0].locale]);
            if (y.rows && y.rows.length > 0) {
               for (let i = 0; i < y.rows.length; i++) {
                if (!x.rows[0].reply_for || y.rows[i].id) {
                  const msg = await send(y.rows[i].chat_id, x.rows[0].data, x.rows[0].reply_for);
                  if (msg) {
                    await db.query(`insert into client_message(parent_id, message_id) values ($1, $2)`, [x.rows[0].id, msg.message_id]);
                  }
                }
              }
            }
        } else {
            const y = await db.query(
              `select a.chat_id, b.id from users a left join message b on (b.user_id = a.id and b.message_id = $1) where a.is_admin`, [x.rows[0].reply_for]);
            if (y.rows && y.rows.length > 0) {
               for (let i = 0; i < y.rows.length; i++) {
                if (!x.rows[0].reply_for || y.rows[i].id) {
                  const msg = await send(y.rows[i].chat_id, x.rows[0].data, x.rows[0].reply_for);
                  if (msg) {
                    await db.query(`insert into client_message(parent_id, message_id) values ($1, $2)`, [x.rows[0].id, msg.message_id]);
                  }
                }
               }
            }
        }
    }
    await db.query(`update message set scheduled = null where id = $1`, [x.rows[0].id]);
    return true;
  } catch (error) {
      console.error(error);
    }
  }

  async function parseResponse(userId, actionId, response, result) {
    if (result.params) {
      for (let i = 0; i < result.params.length; i++) {
        if (response.data[result.params[i].name]) {
            await setParamValue(userId, result.params[i].code, response.data[result.params[i].name]);
        }
     }
    }
    if (result.num) {
        await setNextAction(userId, actionId, result.num);
    }
  }

  async function http(userId, requestId, actionId, type, url, body) {
    if (type == 'POST') {
//      console.log(url);
//      console.log(body);
        axios.post(url, body)
        .then(async function (response) {
//          console.log(response);
            const result = await getResponse(requestId, response.status);
            if (result) {
              await parseResponse(userId, actionId, response, result);
            } else {
              console.info(response);
            }
        })
        .catch(async function (error) {
            if (!error.response) {
                console.error(error);
                return; 
             }
             const result = await getResponse(requestId, error.response.status);
             if (result) {
               await parseResponse(userId, actionId, error.response, result);
             } else {
               console.error(error);
            }
        });
    }
  }

  async function httpRequest() {
    try {
      const x = await db.query(
        `select user_id, request_id, action_id, request_type, url, context_id from http_list order by scheduled limit 100`);
      if (!x.rows || x.rows.length == 0) return false;
      for (let k = 0; k < x.rows.length; k++) {
        let body = {};
        const y = await db.query(
         `select a.param_name, b.value from request_param a left join user_param b on (b.type_id = a.paramtype_id and b.user_id = $1) where a.request_id = $2`, [x.rows[k].user_id, x.rows[k].request_id]);
        if (y.rows && y.rows.length > 0) {
           for (let i = 0 ; i < y.rows.length; i++) {
             body[y.rows[i].param_name] = y.rows[i].value;
           }
           body['device'] = BOT_DEVICE;
        }
        await http(x.rows[k].user_id, x.rows[k].request_id, x.rows[k].action_id, x.rows[k].request_type, x.rows[k].url, body);
       }
       return true;
    } catch (error) {
       console.error(error);
    }
  }

  async function getResponse(reuestId, httpCode) {
    try {
      const x = await db.query(
        `select a.id, a.order_num from response a where a.request_id = $1 and a.result_code = $2`, [reuestId, httpCode]);
      if (!x.rows || x.rows.length == 0) return null;
      const y = await db.query(
        `select a.paramtype_id as code, a.param_name as name from response_param a where a.response_id = $1`, [x.rows[0].id]);
      let params = [];
      if (y.rows && y.rows.length > 0) {
         for (let i = 0; i < y.rows.length; i++) {
             params.push({
               code: y.rows[i].code,
               name: y.rows[i].name
             });
         }
      }
      return {
        num: x.rows[0].order_num,
        params: params
      };
    } catch (error) {
      console.error(error);
    }
  }

  async function setParamValue(userId, paramCode, paramValue) {
    try {
      await db.query(`select setParamValue($1, $2, $3)`, [userId, paramCode, paramValue]);
    } catch (error) {
      console.error(error);
    }
  }

  async function setNextAction(userId, actionId, num) {
    try {
      await db.query(`select setActionByNum($1, $2, $3)`, [userId, actionId, num]);
    } catch (error) {
      console.error(error);
    }
  }

  async function dbProc() {
    try {
      const x = await db.query(
        `select user_id, proc_id, action_id, proc_name, user_name, context_id from db_list order by scheduled limit 100`);
      if (!x.rows || x.rows.length == 0) return false;
      for (let k = 0; k < x.rows.length; k++) {
        let params = [x.rows[k].user_id];
        let sql = 'select ' + x.rows[k].proc_name + '($1';
        const y = await db.query(
           `select a.order_num, coalesce(b.value, a.value) as value from db_param a left join user_param b on (b.type_id = a.paramtype_id and b.user_id = $1) where a.proc_id = $2 order by a.order_num`, [x.rows[k].user_id, x.rows[k].proc_id]);
        if (y.rows && y.rows.length > 0) {
            for (let i = 0; i < y.rows.length; i++) {
                 sql = sql + ',$' + y.rows[i].order_num;
                 params.push(y.rows[i].value);
            }
        }
        sql = sql + ') as value';
        let action = null;
        const z = await db.query(sql, params);
        if (z.rows && z.rows.length > 0) {
             const p = await db.query(`
              select a.name, a.paramtype_id from db_result a where a.proc_id = $1 and not a.paramtype_id is null`, [x.rows[k].proc_id]);
            if (p.rows && p.rows.length > 0) {
              for (let i = 0; i < p.rows.length; i++) {
                if (z.rows[0].value[p.rows[i].name]) {
                  await setParam(x.rows[k].user_name, p.rows[i].paramtype_id, z.rows[0].value[p.rows[i].name]);
                }
              }
            }
            const q = await db.query(`
              select a.name, b.result_value, b.action_id from db_result a inner join db_action b on (b.result_id = a.id) where a.proc_id = $1 order by b.order_num`, [x.rows[k].proc_id]);
            if (q.rows && q.rows.length > 0) {
               for (let i = 0; i < q.rows.length; i++) {
                  if (z.rows[0].value[q.rows[i].name] == q.rows[i].result_value) {
                    action = q.rows[i].action_id;
                  }
               }
            }
        }
        if (action === null) {
          action = await getNextAction(x.rows[k].action_id, true);
        }
        await db.query(`update common_context set action_id = $1, scheduled = $2 where id = $3`, [action, action ? new Date() : null, x.rows[k].context_id]);
      }
      return true;
    } catch (error) {
      console.error(error);
    }
  }

  async function setParam(username, paramId, paramValue) {
    try {
      const id = await getUserId(username);
      await db.query(`select setParamValue($1, $2, $3)`, [id, paramId, paramValue]);
    } catch (error) {
      console.error(error);
    }
  }

  async function httpJob(id, type, url, dbproc, server_id) {
    if (type == 'GET') {
        axios.get(url)
        .then(async function (response) {
//          console.log(response);
            for (let i = 0; i < response.data.length; i++) {
                await db.query(`insert into job_data(job_id, result_code, data, server_id) values ($1, $2, $3, $4)`, [id, response.status, response.data[i], server_id]);
            }
            const sql = 'select ' + dbproc + '($1, $2)';
            await db.query(sql, [id, server_id]);
          })
          .catch(function (error) {
            console.error(error);
          });
        }
  }

  async function runJob() {
    try {
      const x = await db.query(
        `select id, request_type, url, name, server_id from job_list`);
      if (!x.rows || x.rows.length == 0) return false;
      for (let i = 0; i < x.rows.length; i++) {
         await httpJob(x.rows[i].id, x.rows[i].request_type, x.rows[i].url, x.rows[i].name, x.rows[i].server_id);
      }
      return true;
    } catch (error) {
      console.error(error);
    }
  }

  module.exports.getToken = getToken;
  module.exports.getCommands = getCommands;
  module.exports.addAction = addAction;
  module.exports.createUser = createUser;
  module.exports.getActions = getActions;
  module.exports.getVirtualMenu = getVirtualMenu;
  module.exports.getMenu = getMenu;
  module.exports.chooseItem = chooseItem;
  module.exports.setParams = setParams;
  module.exports.sendInfo = sendInfo;
  module.exports.getParams = getParams;
  module.exports.saveParam = saveParam;
  module.exports.setParam = setParam;
  module.exports.saveMessage = saveMessage;
  module.exports.sendMessages = sendMessages;
  module.exports.httpRequest = httpRequest;
  module.exports.dbProc = dbProc;
  module.exports.runJob = runJob;
