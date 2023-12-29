"use strict";

const { Pool } = require("pg");

const config = {
    host: '192.168.101.197',
    user: 'dagaz',     
    password: 'dagaz',
    database: 'dagaz-bot',
    port: 5433
};

let connection = null;

async function connect() {
    if (connection === null) {
        connection = new Pool(config);
        try {
            await connection.connect();
        } catch (error) {
            console.error(error);
            connection = null;
        }
    }
    return connection;
}

async function query(sql, params) {
    let r = null;
    try {
        const c = await connect();
        r = await c.query(sql, params);
    } catch (error) {
        console.error(error);
    }
    return r;
}

module.exports.connect = connect;
module.exports.query = query;
