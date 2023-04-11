# import fdb
#
# with open('setup.ini', 'r') as file:
#     nstr = [i.replace('\n', '') for i in file.readlines()]
#     file.close()
#
# con = fdb.connect(host=nstr[0], database=nstr[1], user=nstr[2], password=nstr[3],
#                   charset='UTF8', fb_library_name='Firebird//fbclient.dll')
#
#
# cur = con.cursor()
# cur.execute('select * from spr_service')
# print(cur.fetchall())
'''
Application example using build() + return
==========================================

An application can be built if you return a widget on build(), or if you set
self.root.
'''

import fdb
import kivy
kivy.require('1.0.7')

from kivy.app import App
from kivy.uix.button import Button


class TestApp(App):

    def build(self):
        with open('setup.ini', 'r') as file:
            nstr = [i.replace('\n', '') for i in file.readlines()]
            file.close()

        con = fdb.connect(host=nstr[0], database=nstr[1], user=nstr[2], password=nstr[3],
                          charset='UTF8', fb_library_name='Firebird//lib//libfbclient.so')

        cur = con.cursor()
        cur.execute('select name from spr_service where vid = 5')
        ad = cur.fetchall()
        text = ''
        for i in ad:
            for j in i:
                text += str(j)
            text += '\n'

        # return a Button() as a root widget
        return Button(text=text)


if __name__ == '__main__':
    TestApp().run()