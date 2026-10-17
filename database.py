database.py


### database.py
### Authors: Janice & Anthony
### Creates tables using sqlite3 and inserts data into them. Interacts with Supabase to retrieve 
### data from the database and display it in the GUI.

import psycopg2
import sqlite3

SUPABASE_URL=https://drjnsdrtqxyyjfgmrqzw.supabase.co
SUPABASE_KEY=sb_publishable_bFQ5tP7jTYYaz7K9UG9hEw_6lj2jM1_

class Database:
    """Class to handele database operations"""
    def __init__(self):
        self.conn = psycopg2.connect(
            host="drjnsdrtqxyyjfgmrqzw.supabase.co",
            database="postgres",
            user="postgres",
            password="Zothacks2026"
        )
        self.cursor = self.conn.cursor()
        self.name = None
        self.password = None
        self.email = None

    def create_table_account(self):
        """Creates a table in the database"""
        self.cursor.execute('''
            CREATE TABLE IF NOT EXISTS users (
                id SERIAL PRIMARY KEY,
                name TEXT NOT NULL,
                email TEXT UNIQUE NOT NULL,
                password TEXT NOT NULL
            )
        ''')
        self.conn.commit()

    def create_table_data(self):
        """Creates a user data table in the database"""
        self.cursor.execute('''
            CREATE TABLE IF NOT EXISTS user_data (
                id SERIAL PRIMARY KEY,
                user_id INTEGER REFERENCES users(id),
                presence BOOLEAN NOT NULL,
                timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                
            )
        ''')
        self.conn.commit()

    def insert_user_login(self, name, email, password):
        """Inserts data into the table"""
        if email.endswith("@uci.edu"):
            try:
                self.cursor.execute('''
                    INSERT INTO my_table (name, email, password)
                    VALUES (%s, %s, %s)
                ''', (name, email, password))
                self.conn.commit()
                return True
            except psycopg2.IntegrityError:
                self.conn.rollback()
                return False
        else:
            return False

    def retrieve_data(self):
        """Retrieves data from the table"""
        
        self.cursor.execute(
            'SELECT * FROM users WHERE name = %s AND password = %s AND email = %s',
                             (self.name, self.password, self.email))
        return self.cursor.fetchall()
    
        
    