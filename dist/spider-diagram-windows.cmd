@echo off & goto :run
"""
:run
setlocal
rem Spider Diagram, all in one file. These first lines find Python 3 and run this same file with it;
rem everything after them is the Python program, with the app packed inside.
set "CHECK=import sys; sys.exit(sys.version_info < (3, 8))"
py -3 -c "%CHECK%" >nul 2>&1
if not errorlevel 1 goto :with_py
python -c "%CHECK%" >nul 2>&1
if not errorlevel 1 goto :with_python
echo.
echo Spider Diagram needs Python 3.8 or newer.
echo Get it free from https://www.python.org/downloads/ and, while installing, tick "Add python.exe to PATH".
echo Then open Spider Diagram again.
echo.
pause
exit /b 1
:with_py
py -3 -x "%~f0" %*
if errorlevel 1 pause
exit /b
:with_python
python -x "%~f0" %*
if errorlevel 1 pause
exit /b
"""
__doc__ = """Spider Diagram launcher.

Serves the app on localhost and opens it in your browser, giving it real file handling that
browsers like Firefox can't do on their own: Save overwrites the current file, and Save as /
Open / Export show a native file dialog (macOS: Finder dialogs; Linux: zenity or kdialog;
Windows and elsewhere: Tk, which shows the system's own dialogs). Works with Python 3.8 or newer.

    spider-diagram.py                  # start on the homepage listing all your diagrams
    spider-diagram.py notes.spider     # open a specific file
    spider-diagram.py --install        # Linux / Windows: add to the app menu (Start menu) and open
                                       #   .spider files with it when double-clicked
    spider-diagram.py --uninstall      # undo --install

Installing and updating also work from inside the app: the homepage offers to install, and when a
newer version has been published (see build.py), the app offers to update itself in one click.

build.py turns this file plus index.html into single-file versions (dist/spider-diagram-linux,
dist/spider-diagram-mac.command and dist/spider-diagram-windows.cmd) that carry the app inside them.

The homepage lists .spider files found in your library folders (~/Documents to begin with; add
more from the homepage) plus every diagram you've opened or saved here. That list is kept in
~/.config/spider-diagram/library.json.

The server stops by itself about two minutes after you close the tab.
"""
import base64, hashlib, html, json, os, platform, re, secrets, shutil, struct, subprocess, sys, tempfile, threading, time, webbrowser, zlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, quote, urlsplit
from urllib.request import Request, urlopen

HERE = Path(__file__).resolve().parent
# build.py fills these in for the single-file versions; when None, index.html and icon.svg next to this file are used.
EMBEDDED_HTML = (
    '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'
    'E87jQ+bR5O9GmMrO+GFNkIcIwhdAx+0tmlE6SzUCnjSXHbrTSUXoHbXEBWdpjCgCijvoZ2Ms+a1IkW3JIYtAGvnZRUh/ZGBk9m6M'
    '1ddihGNeebUTaQJA/LQLfsKjMXmxboQ61BE2/4O3QuEIWjS1cRIsz16c+TgTGOV7jlhqGDau0UYUnX/ASLc/PdTEKLP74Ia3PWQG'
    'SBd5LUlUl3ux1w9eYbH0XrCPUdOV42VjCj5OVmFOs13YODQk+dRddZbZ9mA2+Op+5hYRujjyJ5PUI3D5RJ4IzLFWaM8LlHMtEvaY'
    '0QRtp8zUnNp9E1uB7vxofjYhnMP1pHTE5jjDD+yFuY/CAphax+HF5CyGRnr01o/uLUfpHteDfsxRIMonwg4mmcWc4wcJ72z/YdFF'
    'P3K7YZbYL9O4+Glq/0+TMS8/JoDP8y1Kn1sp2SIkwiigIS/NHpXkefZS7XL/2VQ5P+VTm8yfQTWcREDtQ6S4LiTQ8IwO5QG+p09r'
    'HvrGLsuHQZdR7l3D37x0GHlzcuKZehrynkex+flO4UMKDfglkcILk4+wG0dh8ci9VrMnGo6c/QQFy6L2euET1Lgtbc6fhc7Rv6OD'
    'JyC5Ft2y53jheuTISGkZ7HFOac3oSBawF5sOm0vEJ5F3PIq3R2tbH2ozy7B7eF28hHetpnojV/M47o46TM0r5gmOJjVKBLyVQzRQ'
    '8tHp9axkijbUl7m3RXjDfaysfIJKwkYS0m/YWmaPZFLLoK2zu77wSxS0mQhmiYvxu7WooM/v38ov+YDH7rwkLu6SYocY1ECF2M1C'
    'S4r9/V//+9//9X/8/V//D1C5eXmWqCW3dJyYkZe1WXLF5YVLvCDyhSXloiKmra9q6oCXi5+0+JNOfKHlqgYOwwmJruVbUfiVF0a/'
    '4FXlxAj6xEoscggcnOFlYiRiYmKvz/B3hkSOmfdcmE6TPJlB0tPQ95ScjRM+aDx3rkc6/8dVpBiQSzMRi7cQbEAOEWF0nhHx+kQQ'
    'Ec8GmiZmKnxv+MmkR4eUVcfBPPos7VHedkEVkxEkP5gSNI4PoedRMFN+lBmVoWuSV92gzMwxP5i5dLbBFpyak2W5au2ABaTjYwwN'
    'ybr8YyBHThpuqJYOEM4E5HeGGGTrJC5R/EOzn+b1Ht55/++V9zQPBjr4SSUhb4ZPOCTNT15qwpv9CDDsRvJHFjiQ0AjxaRhOkLzl'
    '5PkzoPFrz9ekk1uRcC9DUmg6/GSgWxxQ82UhjIaYYxhB85lxRmbQlWkqYo6G41hxH6kABJWfkGphLUGfB5Y8B+68kOwHGmGJEiMe'
    '9ULFVl12e7rUcLKkZ/ItWdoxx7e4GGv9BH9t3AV6v6zvgZdiHezDj43bdxP5MJe3z0ux9m+XpGVAy6i3tkNKqMQz28UW9I9ezJfO'
    'GfNxfsxukj4m5p7JmRpz/E/QArlNFlgTy40j64FHIsBkT4kxJHQ4ex99FxP3RadCz9IcJJMPGKO1MYHJMhWuL2/tnbIrDJYWUbb2'
    'HsbtfqbU8k7bCC1mIwHQ7vBjabZij65VSFzz9suyGzRSgkd+4Gh2P0+G4IWp/PCiBnZwiYfTP7LDsyaaNmnShk7CYJyWmG5wIRb3'
    'hfhtgTvHkTvwN7oXuiQwLoTfCSR0SPhcekQ/+Jh4QKDf5AB+PR628WESdKmYhP2zABb4PP0IkSzJTWunclbyvKjMcsGDe/guePHD'
    'ySc3E3ysJDyc84V5iD8s7qzs/wcmjS4Ai0VERhCRc8+qxLHk0GvaP5489oclpEeMpP2kiER1P2PfoPDdDUUf6uTnyD7UbUi70U3y'
    '9PQzmzNvjhgmkgwmdKOI5A0kCV6341isLnwZD20WbLt5dd2wqHeeNsn7SNdQl3rndRkAH6rOVjFsYOk0rrkxbAlrPXU8892xQWm6'
    'HydsbYfmhA4LmQ7E9oUC2xk+rQ3rrM2NOMSSa10i/X3fwRtaQG0PyDXO5LPFiClpFGFPWOq/pBlmye0mzKVS81mgj8YOcdCfuCj8'
    '5S9oPf7rX8Nrsp0FV0G00gjknUFtOjZ3nYscK9ClBhjWr+FNTLsC2/p3hT//GTXnP/95u7i1t2TI5OW8lbYXECgrrSxdB9OCZGD/'
    'f/+fBKzwg7Yc5j9imGFERNdBpQQdI6HEkd9JZ5FLXVG1OncWAXI27OUkqlrIdvV7iYxRkW2KZcJAr5De2NQpSnzsCV/40ZWfiXYs'
    '4NswORd6I3H/OIVOpbd3yXGZfItCJ5Mxc56LUjxEzkYsN0ZsGQvGQa5dLDyGC1PumBMUFh2LrlnIrAi0wa1escUKnh1gvGgmdcvC'
    'Xa35tiysvdySdWnwoJb4gDLaLGHnpENmWN5o8P/IPbp+kqkrFytxDshf5XczHME+/SyZiQp9JXwZZyZSUiSBr3gyqSy1wKtDSo0b'
    '5eD6qKZEmWMSKfuZ5p3OOJMdlK1N0smNaGSY3hL/5mc0yixvCiuOZoGn5aY7gpfXNHT8m53tmIB4XpcliVx4jraxdwiscWvvb78I'
    'W1w1/CpspakKvagSPlwK/uRBEehWRS5extAFkcbE3zij5HdFjsDYHL+Cmh6SlATP+O3a9Azt2nTlFqvMPMe2bBjdmY4dqviTew+F'
    'HYr8i7BlYhlxl77TTS/QuoQ8i3lRkIMLezuLC87jr/xG0a+CDaoQezQADYeAxDM99ohuxsBnv8ptWVdl/pgdTkZtRa5m/zQWRaXT'
    'l/eecPsfkk9e2rOKlcCEW+ybu0cR4CwfKPnomOgnGtD97+jJH8R+v+hGwNzGyN084WSA5O0bVNeHbuOHzOugyHt1eadji3+xzOj6'
    'debfJrDn7T0WrgdshVdt72Wixyhclzs/xmk8sQbZ8LhtgMJx4gyTLoV5h33EVvaokxBSACyC8JFu68Pj/rAi5emJQ07j2nzx+YyF'
    'm3GAsRo9dMSOWpDjYTG3aH7bYBhwxxNghMWjyMyVgB7NXMMzKVSk6xmGNf+aHupr3CkeR7GwEForJjCEhY/NIC4ZXvXGXTQSi84y'
    'KGThKMHibgFW/jPRmJSmFylNL6jYs9RR4d0sMcUU5KJal6tVWZHVclmSK2LZKEhqTEcFqVwuipKkKJJYVcRKPUNXYpaCDFGRFGkj'
    'CnISCHpAyKUlLnYI7U5B3iLcplAMRhhPJcpuuh7nwQAKpcRJ3S6F7wHWhtXSSBlWdChoeBawdLq5qDp3Q3xLo/pig8w7vBiV4BeU'
    'psvxmFPmEoaMdXG5o6kCTuLQSXI0V7vxTBF+UewK2/9ZmioacyoVLwwrhtnvxJB0KL+eH3OSGMfkNI7JaRwLjwbJxkDXwRRY3pIE'
    'rilitVirVCRJrEn1qiwpMZYpSrEsinWlJlXrdaUiKmuxrFaui50Mlkm5WJZkg+GgEdwEb0hgHYuGD76l0uQKnMs72YXUU+2wtC48'
    'GFPD+8iMPPQ5ZO6LvM+wQXSJT4DEtY8YIhaGndfeE/LBsBm8a6yA4TxxW8DnviRDX0BUXghQhwcYQ0Yyi76biFHn2wELMMG9ZogZ'
    'fsI4WBx/jwUH8OFECTWmDosd8qPobJxRUtPWcDMljWlKGtMoSTBlWdKNQDOtFDMrF+tiVaqoFUWtl2uVWgLFpIpcBP4lqsDnZBkY'
    'XXUdjnXFWkcUMzgm5+KYu0dgRfjCA9GhVJTdzrGTO2i4XDvX8Tq1Nb3H+Irg4/VBUaG//7d/S62mls3rTBSes+uWEnvmE8keiQwO'
    'lEaZbselkFqbTK6CGqN4iDMY30HDy9mLqRWeuoEFp5G3LiWw6wP+z4Fy2gl2Es0x9w0KhUK+9Gp66dX00p8yDS2OyY5yQf80JFA2'
    'QgIxAricBri8iKtx9CBPW8HCKf6dIZYiiCtpiCtpiC8WPa+SgNYoU1NZqpcVtVouV5JyAryq1asqSAoVkCfKFXkdfVUqWk3sZgBV'
    'cumLLECcWQSoZYffvegh7IuY7o1hGvyMnpOokH1eimqWUu21HX2+0LZO1sVIoCjF3C6WE8LG9LhSQjqBOuk9P1s8hifZ7VFyn1/R'
    'wzltOSSVJPf5XeFYRs5ATmgf7PqaiyIs3HQtBHlyzWYdMcvniqZTBTZt9cqZJDPgm5GGk9cDu9oFoz4/2AtxxSgn/YoeMtx4wyVA'
    'GljX6GemnPyASgJzplnXwT6UZA47H+2FXQNcYpsZvxB4XW/fw94KH+ytiRlBS5QPdF0fr2EfDGlfP9gTJY8v8ZTYa9fnId3Zwwc7'
    'Q3f+dV3cfJSrsHi+MJi5BDyjM0Z9di2upcdy9FFqMYP4cvN1fYkbNF5KsutSco9Ae4uRkNX5XpaQtcKA+GR6GjoJS6XNiXJtOZgs'
    'JEoVyvJM5ChJ1fTmWk1vrjIarq60AYnzlF6q5zh6YoOtFBXYVFFFQk28ripZXVxUqsU6aD5qWZLqdbVW+4lWrs21J56sM7wQNp5V'
    'zwiD5fleWRQoFVoyP2YkI/ccIU5o5kGJNuZyTFpIkgLoPSsQRmTGfbrjIGUvoTMMXDFKrpWjLoWtx75pYcaGqNHdOAuFjvYyNBmR'
    'mVNIJJVJpF3jaJSBO6EYYpKGfJuX4I/tEgZ0RGmTKGLE8PNiRdYoTrU09tXS2EcXfCfFuSoIbGWloipSFUROuapmsU2qKkV1BbZV'
    'N7P9RPDV0/DV0/DhZeEpYVOuF8V6tSyJYrkm1hQlBVq9XqzIYq2qVqqVcrmWNRjUPmKWYrecQym6tTy2qmXM0FLGDr3vzJLwVutF'
    'VRIrak2tSeVqtV5NwitXa8VyTVVqkqxU65Xqp8CVMuDiFeoxtFkjYMYKyK9RT0Bck4tiTZQlVVLFqqjU6ymAa5VipaqUlapSqVWr'
    '5c9BLGcgDi91j6HOmJWkjF0putc9AbcsV4uVmipXFVWtKVVJTiNtvQaYoVTkOoAuVdVPwa1k4CZwYqAzFgopa6IANPKF/0ICTwJu'
    'qS4WYenLoEXJolpVq0n1qabWizAeuVKpy6AHytW1tJZrAYthzKjSUkaXZneRxsCpUr0oVaUaIgLoouUUMohyDZTQqqxKZUWpqWqW'
    '2iRlI+g4/dDdf3gQRSDEEGd0aSmjTNO19klzIhoNpXINoFbr8H+tnAC5CvRWk1FhrpcroD/XPgexlIZ4SiDEEGd0aamSZRB41z0T'
    'swEd2iQQJ7d7saiqgKhlWZFrCpBcYgDAR4pAfjXQpUVRrSufHAAnJ/Lcj0/vhNAzP/mIYjqgRjy8jDQjVbMMmzlpJZmgVJaKMCBY'
    'lTrwblUuJ2kTlqoInBz4SUUqV6R6fR2Or7LAmcNeCB7A7uFYttAT5CvzP3hzjd63tuYbFXW3VH8rqY3G3cPg9fy+19hv3DXgF3w2'
    'Dktq7/TloXl9+CztPzyKr+ePR014dwQFTs8a9M/dtNHYD9r2/bw50A/OjvuvT2bjFNqD+kesSGO//6JcTxub/AN914MX+oT+Hy/v'
    'Gj/hH2vw+nz9ht9q+Ofgfv50bGkI2DGBd2+Hvy/YbzP8fct+K/rpvojfmuz3vHV8fojfXqm9vp35bWZ+v3VOz6k+AXE4C9qnrbcY'
    'Ppqnq9encqtJs9TDP53G6VWj2ds/bRydvzy1nF5Yul2BqT98k7ClAZvvcJ7NIcxXoDaxJw3HcBa+OnjA+rd9+BP49VR7qfl+3u93'
    'hkfxYkDN1yG8v72w4fv1Ezw6quNjtx3Dv796PAcNNp6jTqM93Z80TuCzsW/h84e7/XHj5Kpx2YNBH541rhqNWeOwXZKn+zB/zcN9'
    'RLZp8wg+j/fvmif70+nZ/rRzuj+tXR5MB1dHd7WHo/7R7dH90eNxf/p8NLvTju+P7k8Ojl5O+qJ+Oqt1j2Yd8/zgzDjfnxqnsypr'
    '+64J7XWgPfXsoKEax/tHzdO+avzY/9USDPf+oHE4bTz1DhsPMPt9AH12tF+q3TVOpkRb0Dc8S/1zdbR/93La6J2WZo3GzhHSzvQO'
    'yt4BfM2zRkg598f9Ru/q6KjXPDl7PL7vNI8Pehog5v2VeSWfzwfto+b54flDr9d5OhOvjwbj01lTuZ1i34BESI/HjHaT/xwdQF/H'
    '+73OGZa77sP73hHAeAdzfHUU9b0P9XsE5wP0vd98Op71Xk/6+zPo2zu9Vx9u92v7d09X4vmjPzktyT1YyukRjv/w6K5Raty40ol7'
    '35tVLt7f3aP6/aj5cnVy9EgPpy/3t03NOjnc7//nfnPXfDm6OnNH1w9D//DpoG89nFfemq7XkHpXZzZ/3JiahiNdaNPrl8OD//Xf'
    '9+D14fn9vXN414QZeZgHR3Lvev+xqfX7/ym+lbSLi1Fl4Lruk9uqDu5Pm/Od26k3bncfJO1BG1nVUfNmrFbf/Pa+o0l3prQzDJrV'
    '1s2tPJTns+uDN6Uzmyiv5eZM1P13sfv0aGj3znWp+apMLOfN3VGeOpJZ27efBw+j8XA4t0Fw7s6v5rarP+0EwzNz1u6q9kOjNpxP'
    'tFvPqrhyRXXeRubwvDQ9eL+R/OqFprf7reZ7S3m/rZ6Vjbr4Pmg6de8skKajy8fae6tsn5afziY7t68j93Hn9Ua6fb+p3c6hv7Gl'
    'aZXmyH2e3Der71eiIg8r7ov3tjMyL63bx6nyWjt/61eO3y7l+2nVuq1cvd/f2qferP74HsCy6cfvzwfn94+twYt++2K3W+3a+Z14'
    '41YvnfH4Zeirteea5vXF2e3NecV927k/nxpdVyo1xjvVyb3yKD4q4YQP1deeMxT3nQvtrXl1lvzWcEcHJ0dNRuV3gCX//vQKC9rX'
    'RoAJ91Lr6f6w+iLfPgb9y8mZ2xzpVnA9aVcOG9Jz80K/nVbHrdbcMV+rO6PbE2N/oBrXN62u489KwcV1ffZ0et9/Ca6Do0fdkIPu'
    '8eNF49Z6vpxXx69db6K4eqs5fr19vTwewuKbSrt/fwpMcjav4C5q7Tj+/lX37KHedjVFrx8Y/cfR4VHZnFqlNy+4vBmd+/awL93M'
    '5KBVaY2ssVvaf75qSvfyo7hzVOvWGqK4M1aPb9p96W5iuupMmdXf33Qaaffx8Pa8mc+d9vvH11SoeeX9B/DHR12/FN1g0DKsUbPU'
    'lC5PpEpn9GCfjcXLinRZskpyxw1mj61n5+b++Pb6/rZ/3Hy8ddr2a+UFNgjpqj4RB0qvcTuc1p/4zjO6vxi17o1y8+V0Nmi57VnV'
    '0na8h5E1f79vdcZNsdkpD8/eJhdtq9kU32FZe6pCIJ1K4vvsPA/g45PGC2NpL9f7d5yl4W8opTXE45PeNRS4xgLwc7//7/r+QD7W'
    'n0/n2uXEuTeU+a0Fz586gGfz9nVrWD50R+aLPbZ7z5et+Uh6Ptavai+W3RRHVuuideY5E6133ZrdvFgX529K6/W29ayeSLfD2+fg'
    'aFK5tqSXunxzuuPXj2ZSqTsa1DWxehuUpeFlcHrrvo0GjYY4Q2GvISk3Sv1Kv7y+KD151VLj4Eo5n4gvdVerSLVB/cK+fT2ej0vG'
    'aNyqV3bU+oG8L+vj1/Hr41B5KT0Gc7WqOeXLcfm9fHpVfdDcxzf5fFY537nxxLfa8Aa5x3VDO1Qs2744DxrawdvdSY+zFXgBO1H7'
    'Dp7BJ76gfcoBcbcd/gg5ENuqsAG+gf3HltgfqsNuJzizjmfHnlOvnFxjIWnH1Z5NzX6tv1vN+9ZjZaY8vvfmnefLyYtllF5HzWEl'
    'eDVuO1XPPJv0W/Kx2Dq+h/9vDKmnTQ3j9dmfzEYV+2Xy/njaurpv7dTPxbqnydXHg/GTOjTmrR1xWPLGcuXIGI+H9ntzWnsbtPWD'
    'a+1eq0xOx3cSQn54JZZkrdJ9k2bPA+m983xf842Lzo77MtdH/rB8UtVc05bsHaMxUS6tysRQR6NJBXCUBls/9GVPN81LfTw8c9+s'
    'o85Zrzwcj0bl1jVyxWiGDtQ536mf9r0Q3XEoRATwbX/gONMX/A8Xdd982+9N//N/Npzp4QGt9cXVycVJ68wmvJy+WMABX078Y8YL'
    '/xf/tn/fu2NkN0LUPnk+ekDG9USM6xxWssUY1xDWt0WMC98fdd4HV4eH3bo7r167zXpLE+XS5eT61qo/1x616uXFs9/vjsUre/Iy'
    'a8vdt6fbWuP8+ci4PZ0fXNegp5uruRH4/VZJr51I96XqhTUq3b89l09b3SvFmA/rbd+tz2V71pH0d+3xwNl5erXHb1Wn7VZOoP7t'
    '1aV9XZs8l47nN3e2qsmlu1l12LWfbwPgXl7pWB89q8PzVtB6fSu3OzudQ/22hUhavhi3BqO3y8GzVfKazfLN44Mnlo+l41rTawal'
    '6b4klmqN40qpBz2J2NNF5eaxfPG2czi4cm8v6q3a+7lfv6u9a6X+e9Usvd1fTKS7sdhuPZ3vaOZLbTK9FuuXMEunDfnGv2k57cqD'
    'fTp265X+RGzKxrkUaK3BvHYysmejoHU2GT+Xh7om96dt+0Bz3yZv1au2KyHXkW7OpdupfDe/HHivo2fxWWs9KnVlcj17HT950sHz'
    '5fXcLN9NvGbrbGSosmVf+Iqqj8fnVfeANhRcvuNydv3Wre8PvodnJ0ddHIAX8vJH+rE/unmp9FXv7cIKFE8RrfLNjqTtBE3brhzB'
    'fjN5PR6/P06eL6xT7ah97lw935YP96cX1/7kPHgaz0T3yavMdx70in3YmUnd+cnLSHyxq7a2U/Ekr9q9rx7aFyP4x4L/n0auIbVa'
    'hvRoX000Tbm/qb643fbtwe2lXW/o3vz5SRpZx45aOh55zztGVT6Hpktlp1OdnzZvL8ue25lXPP0AOPqOY4+rrbo7mnbKg0pglU/f'
    'pfl4dHPUgO48+NdpXHey9qjmrAb4IVXlS2kutVSxdWHuqMODl9Fw+Ny46amlUdXqvI7ac/G1dWCYwcmodH1rlsXJif7cebYuva4y'
    'uyhN6sFt2a093d702u0T6f1qtnNSn9xLj7O68QKyaUsfV9sPZc1zx81LpdUcVS6rj1XtcH4JMv5750C13o/mbcvtPpiX9Vb3+qb8'
    'ONo5ryj3lXb3XFVeQXd5kmpad+CK4/Pg9E0xjhX1tabWpvoA8f9tf157vPFdY3ZZP668zdzncU2snwZXb0+HXVESpftJc64enMNO'
    'fjDG/eCJ4YgObIZjxjPbGQhf2M7w0RKnN3pTb8o3t8rs6vSpbp3LsLBe+1n1Tkt317eDSt18qb8rnfer99Pm4Ui+br8/X3f02fFh'
    'uVUtHbVO3aCpB9rOu2ho9kX9rt5+bo+kl9JR09OcqjWR3Ppr9/z2vuzJO/czWNpxtTMaP19URpWKZYxAK2u1rMfn8g5s1IH4Ujox'
    'Jk7p/Gqu779PWpOzTs9q2acl/Uo3ZqPjnUlzIHXPJ1qnMtG8UaNjDV6vlfORUg0eB71Gw19jxwz65afHvjKYvAQ74/fOozQ6fqke'
    '9o3x8f1F+/lCvp7c16+1xwAQY146Uwcnr+brzr35UG09VG/e5vvV297r+NyWm5MX4749aRqW1qo2a2JVrLuDK+NCle8HL4F0Ob42'
    'xk+aWNdMt/msnD7WHqWZrVaacq0i3VvieWXebXnt+vGNO7t2L1vdg9JJ9fb5/Q1kxONz81G87s3c8VXFU5+vNbvull49c8ftPj4T'
    'iyrfBdf6Rat5AeKqU7mwNXO445evR6XDQLq/7bROp9MXNLHUaM8dOhKIVP4JVzPp1R2+eTsp31o3N+rcAtZ2EcjW89h9DkbP8rls'
    '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'
    '7/8DoqswnQ=='
)
EMBEDDED_ICON = (
    'eNqNU02PmzAQve+vmHoPDVIx32RZQQ5VpZ5yqtQ7AQPuGhsZZ0n+fccmVN10Vyqy8MybN7w3Bsr5tYfLKORckcGY6TkIlmWhS0KV'
    '7oM4DMMAGQReOVu+qktFQgghT3GRwwNA+cn34cfEW6bhG697XY9QTxPwRslnMAMDLn0LCNUr2DnAd/F8HU9KYBlXyy50MKPwbLoM'
    '3DBQ0nVj6+cZddx1Emf2BeahbrnsodNqdJy21i/+qFpkNw2TBnaPafPUdp0HRjmG4P1g7ihxlifs5FHwfTdIy7r54JRKwSWr9XeN'
    'OpbL24oYLhiBS4TzE7iu2yVeM9wicriZLGejJlBdNzPjyjb3GyWUrsjNFwneZ0d37NXixi6Dt76c62CzXWrWGMD3E6Mjd194a4aK'
    '5OhhYPYA1lgjJ0oJdFyIipy12D3a4bxVpuzB6FrOndIjTm1DURu2i2KIYpp5MDe1wJTmeb73tqdIJZn1rtULQ98djnjL/JuLmEZ/'
    'IDtGU08V0eos2zfwL8Xlht+mbrhuBIPG2sapmuu64/kkaPm9ckIzV0eTd4w4XBnFX/V/Vfa23+kUHz4p/w9O+pHYVJsB8KM64qkW'
    'PzMaHaOUPkEU0kIkdO9HNDlGiUVSmooYA0yOWI5XxN+gwiLYBRnNoNgUyqA/PJT2tz08/AZluheo'
)
EMBEDDED_ICO = (
    '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'
    'a0HY54uPN/Cum670c5vvsWKRNZ9zQkeSdRKM2d27Ih/YE65FYB3j10so8Kc68j06K2YvJ9+G71v7saAcvacSZNEHfdW6R8J1DozZ'
    '3bdyFLAnfe6P/Y9WjGDyI3VVkyn00RuRNYCP3pQ6aw0AstJnZFvrAnYZe9VoYE/9WT6f70/Nk33Ewic+FlBGnYyV+nN6jNndv3oM'
    'sKf8fHzVKAo8OoPI2STPruWZNpdRh7Y0nrNjzO6BinE6cyStPSkq+Rr8+iY+z74QUEZdmntR8Jhj9UDl+M7M7rT3hKgaT8G62wT1'
    'bDbtvSAwZuegel5WmdnzzvGKzJ6XViCn2sijz+N3x9eY146xMKY8mwqqZ4QzQusntzCUY1owVnCdypnF8zLJNa2e0omZwThy+LzL'
    'YYzRKRz1rC4mh7emMI+poJrC3cwRxt5BoGM366wU3eLvlLjc2qjna1qoejKes3RmdKZ7B4GOzsHqyUZuZ+yzsp0qJ++y8/A8A7lo'
    'nTAL/66RU2Y9p/hW/HMKY44unJlxbaczs3r0PjOzRyHz/TQplL6sw3rmgbn4XJWrw//Xmbr64p7H6mf1dDGeNHFxX4fS0UtvMHWr'
    'OT7+vzOL8/mdopN1N87L68Tz6bpsz9V5jlwH3Y3z+vVmHAl/I25uH6a3ek+nTeh3jOnF89FCxpVortpS/SPy8PyqpW6W9ZtX5m9j'
    'oU7aWCbJPBc6C3muWcR44n4/adlYNXfCbyqcOU7Nld9TcfaIq+cy6tAGGcgm+D0m6CziuRzwxMZWX08tqwvltxqwBzXie50b71Bz'
    'R8Rdb7xD6mQvbJaBrMxrY+eJ0FnEczngiYtX5vmO5zcrKHjkrxLr43mpkud2qg1l1KENMs0S2xsX7wydRTxvAp6k878lw8n39maJ'
    '+8JvtsjvtnAZdWhrY74HnUU8HwIemRfFcJPQwvMYzxN3yv7VwSPvCyijDm2mXHx/0VnEcxngiZ3jDCaXbZzsLY65GOLtcKxdqyYI'
    'KKNO4jxZRmQltjBmnuQR3UuHAk/0/Mj72BzZX1T2Mf1gq8RQym+wPDFPkDg5rkObKYc+reZD0FnkLhsOPG6137DMURDrJfOaxpMq'
    'TuGtpymE48JzTZmDchl1ch8IGZZFH5nfmHqUziK+1weeyJ68w8n/hxqJNQQoIxbLW8Xn6+d/FVCWmC2Ra4rIYa4RmUdAZ5HXVgA8'
    'MXudYv7w7ELBjH/yrZkqe1UDlK14qRi5mHgk6Czie3XgiZ8j5CuMuUHw7aeJED/JoGzd/0fLxQKdRXwvDDxt33uPptC+V3heVy+g'
    'LPsjtn2fDZ1FfL9byLjavCcuH8P38T+j8N/fFFCWurbvo6GzkO9DezOOdvez4vtka70b5Xb3v4JO6J7Qie9TN2X7XpR11kG3sU6t'
    '8/3hzizea+4UneuM/ZrUfabO1IWrCx18P+RiPGnikr7VUzZBl6z5GvfR5r0VbZzWiWqm9ub7rkKmKE0KpS/rsO4JU9yHpSOv3mp5'
    'SO7ArPuwbyS+D+N7p8v5PqfgzKye5UwdU5sEtJWLLPqoNY/L+b7lbi6fTiNH+TT68H3U5Y0leQWNJX1PWzmnuE+Z3Ysa5/SO5KEi'
    'Jxh1c2NyU0+jb9P8/uWRXMN+dHbBYHI+Op/OrZ5mPZtHGXVoU3VWbmI5f9fXxuSuPb2QQnyd97//Gn9XDxRQRh3aWuW81fJ3bW10'
    '7pKz+jZ5lhr8/ANqWTlRQDnw6bvS1irnqbbl/ptq434vqTSf/Hu2UNC+X0BZ5bLE/R5SrXPx4NpIrsEQ9V24rIACf/kt+f64SUBZ'
    'nh1ym/UbKopa99JhtRJnvmQweZ+cTyGMefgv8gw0sOdlAWWp4zbIQNaITa/1LBtRK8+/+DvK//xy+d7CszJv7e0U5GsekDKen3Eb'
    'ZCBrPDOr5e+CWvO7wVc+nvxPlpBv/S38vcH3cR9uE1BGnbSxTNR3SS1fi2sj1+bRKm4RPMz3YqfsAspW/eqY63ttoHJcecLYtjWT'
    'KPRqlYBykpi2cp73F/C193TC+KOqcYrEsUmn0ZevZZfzNeduviacTiNG5TT68DXwcolF2Tjtcr6OFfC8tJypbYdykUWfLFyH/h+V'
    'j56/'
)    # Windows icon (icon.ico)
VERSION = '2026.11.10.1436'        # build.py stamps each build with its date and time, e.g. 2026.10.19.1534
UPDATE_URL = 'https://raw.githubusercontent.com/WMBanner/spider-diagram/main/dist/'        # build.py: where published builds live (a folder holding version.json); '' = no updates
PORT = int(os.environ.get('SPIDER_DIAGRAM_PORT') or 47615)   # fixed, so the browser's autosave survives restarts
TOKEN = secrets.token_urlsafe(24)  # only pages served by us know it, so other sites can't use the API
IDLE_EXIT = 120
DIAGRAM_SUFFIXES = {'.spider', '.json'}
SYSTEM = platform.system()   # 'Linux', 'Darwin' (macOS) or 'Windows'
DIAGRAM_FILTERS = [('Spider diagrams', ['*.spider', '*.json']), ('All files', ['*'])]
EXPORT_FILTERS = {  # kind -> (file-dialog filters, default extension)
    'png': ([('PNG images', ['*.png'])], '.png'),
    'md': ([('Markdown', ['*.md'])], '.md'),
    'txt': ([('Text files', ['*.txt'])], '.txt'),
    'docx': ([('Word documents', ['*.docx'])], '.docx'),
    'zip': ([('Zip archives', ['*.zip'])], '.zip'),
}

def config_dir():
    if SYSTEM == 'Windows':
        return Path(os.environ.get('APPDATA') or Path.home() / 'AppData' / 'Roaming') / 'Spider Diagram'
    return Path(os.environ.get('XDG_CONFIG_HOME') or Path.home() / '.config') / 'spider-diagram'


def documents_dir():
    """The user's Documents folder. On Windows, ask the system: it's often redirected into OneDrive."""
    if SYSTEM == 'Windows':
        try:
            import ctypes
            from ctypes import wintypes

            class GUID(ctypes.Structure):
                _fields_ = [('a', wintypes.DWORD), ('b', wintypes.WORD), ('c', wintypes.WORD), ('d', ctypes.c_ubyte * 8)]
            documents = GUID(0xFDD39AD0, 0x238F, 0x46AF, (ctypes.c_ubyte * 8)(0xAD, 0xB4, 0x6C, 0x85, 0x48, 0x03, 0x69, 0xC7))
            found = ctypes.c_wchar_p()
            if ctypes.windll.shell32.SHGetKnownFolderPath(ctypes.byref(documents), 0, None, ctypes.byref(found)) == 0:
                path = Path(found.value)
                ctypes.windll.ole32.CoTaskMemFree(found)
                if path.is_dir():
                    return path
        except Exception:
            pass
    docs = Path.home() / 'Documents'
    return docs if docs.is_dir() else Path.home()


CONFIG = config_dir() / 'library.json'
SKIP_DIRS = {'node_modules', '__pycache__', 'venv', 'site-packages', 'Trash'}
MAX_DEPTH, MAX_FILES = 6, 3000

last_seen = time.time()
live, closed_at = 0, None   # tabs connected right now, and when the last one went
lock = threading.Lock()
summaries = {}   # path -> ((mtime, size), summary): files are only re-read when they change
last_dir = documents_dir()


def applescript(text):
    return '"' + str(text).replace('\\', '\\\\').replace('"', '\\"') + '"'


def pick(mode, title, start_dir, suggested='', filters=None):
    """A native file chooser. mode: 'open', 'save' or 'folder'. Returns a path string, or None if cancelled."""
    start_dir, filters = str(start_dir), filters or []
    if SYSTEM == 'Darwin':
        where = f'default location (POSIX file {applescript(start_dir)})'
        ask = {'open': f'choose file with prompt {applescript(title)} {where}',
               'save': f'choose file name with prompt {applescript(title)} default name {applescript(suggested)} {where}',
               'folder': f'choose folder with prompt {applescript(title)} {where}'}[mode]
        # 'activate' brings the dialog in front of the browser; cancelling exits non-zero.
        r = subprocess.run(['osascript', '-e', 'activate', '-e', f'POSIX path of ({ask})'], capture_output=True, text=True)
        return r.stdout.strip() if r.returncode == 0 and r.stdout.strip() else None
    if SYSTEM != 'Windows' and shutil.which('zenity'):
        args = ['zenity', '--file-selection', f'--title={title}']
        if mode == 'folder':
            args += ['--directory', f'--filename={start_dir}/']
        elif mode == 'save':
            args += ['--save', f'--filename={Path(start_dir) / suggested}']
        else:
            args.append(f'--filename={start_dir}/')
        args += [f'--file-filter={label} | {" ".join(pats)}' for label, pats in filters if mode != 'folder']
        r = subprocess.run(args, capture_output=True, text=True)
        return r.stdout.strip() if r.returncode == 0 and r.stdout.strip() else None
    if SYSTEM != 'Windows' and shutil.which('kdialog'):
        spec = ' '.join(f'{" ".join(pats)}|{label}' for label, pats in filters)
        args = {'open': ['kdialog', '--title', title, '--getopenfilename', start_dir, spec],
                'save': ['kdialog', '--title', title, '--getsavefilename', str(Path(start_dir) / suggested), spec],
                'folder': ['kdialog', '--title', title, '--getexistingdirectory', start_dir]}[mode]
        r = subprocess.run(args, capture_output=True, text=True)
        return r.stdout.strip() if r.returncode == 0 and r.stdout.strip() else None
    try:   # Windows, or anything else: Tk's dialogs (bundled with most Python installs)
        import tkinter
        from tkinter import filedialog
    except ImportError:
        raise RuntimeError('No file dialog available here; on Linux, install zenity')
    root = tkinter.Tk()
    root.withdraw()
    root.attributes('-topmost', True)
    root.lift()
    root.focus_force()
    try:
        types = [(label, ' '.join(pats)) for label, pats in filters]
        if mode == 'open':
            chosen = filedialog.askopenfilename(parent=root, title=title, initialdir=start_dir, filetypes=types)
        elif mode == 'save':
            chosen = filedialog.asksaveasfilename(parent=root, title=title, initialdir=start_dir, initialfile=suggested, filetypes=types)
        else:
            chosen = filedialog.askdirectory(parent=root, title=title, initialdir=start_dir)
    finally:
        root.destroy()
    return chosen or None


def dialog(title, save=False, suggested=None, kind=None):
    """Choose a diagram (kind=None) or export file; returns a Path or None if cancelled."""
    global last_dir
    filters, ext = EXPORT_FILTERS[kind] if kind else (DIAGRAM_FILTERS, '.spider')
    chosen = pick('save' if save else 'open', title, last_dir, suggested or '', filters)
    if not chosen:
        return None
    p = Path(chosen)
    if save and not p.suffix:
        p = p.with_suffix(ext)
    last_dir = p.parent
    return p


def reveal(p: Path):
    """Show a file in the system file manager."""
    if SYSTEM == 'Darwin':
        args = ['open', '-R', str(p)]
    elif SYSTEM == 'Windows':
        args = ['explorer', '/select,', str(p)]
    else:
        args = ['xdg-open', str(p.parent)]
    subprocess.Popen(args, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)


def write_atomic(path: Path, data: bytes):
    fd, tmp = tempfile.mkstemp(dir=path.parent, prefix='.' + path.name, suffix='.tmp')
    try:
        with os.fdopen(fd, 'wb') as f:
            f.write(data)
        os.replace(tmp, path)
    except BaseException:
        Path(tmp).unlink(missing_ok=True)
        raise


def diagram_path(raw) -> Path:
    p = Path(raw or '').expanduser()
    if not p.is_absolute() or p.suffix.lower() not in DIAGRAM_SUFFIXES:
        raise ValueError('Only .spider files can be saved or opened this way')
    return p


def info(p: Path, **extra):
    return {'path': str(p), 'name': p.name, **extra}


# ---------- library ----------

def tiny_png():
    """A 1x1 grey PNG: stands in for bubble pictures in homepage thumbnails (keeps the list light)."""
    def chunk(kind, data):
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data) & 0xffffffff)
    png = (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', 1, 1, 8, 2, 0, 0, 0))
           + chunk(b'IDAT', zlib.compress(b'\x00\xc4\xc4\xc4')) + chunk(b'IEND', b''))
    return 'data:image/png;base64,' + base64.b64encode(png).decode()


PLACEHOLDER_IMG = tiny_png()
PREVIEW_KEYS = ('text', 'x', 'y', 'parent', 'kind', 'color', 'order', 'collapsed', 'bold', 'italic', 'size', 'shape', 'fill', 'imgSize', 'line')


def load_config():
    try:
        cfg = json.loads(CONFIG.read_text(encoding='utf-8'))
    except (OSError, ValueError):
        cfg = {}
    if not isinstance(cfg.get('folders'), list):
        docs = documents_dir()
        cfg['folders'] = [str(docs)] if docs != Path.home() else []
    if not isinstance(cfg.get('recent'), list):
        cfg['recent'] = []
    return cfg


def save_config(cfg):
    CONFIG.parent.mkdir(parents=True, exist_ok=True)
    write_atomic(CONFIG, json.dumps(cfg, indent=1).encode())


def remember(p: Path):
    """Note a diagram you've opened or saved, so the homepage lists it wherever it lives."""
    with lock:
        cfg = load_config()
        cfg['recent'] = [str(p)] + [r for r in cfg['recent'] if r != str(p)][:199]
        save_config(cfg)


def scan(folder: Path):
    """.spider files under a folder, skipping hidden and bulky directories."""
    base = len(folder.parts)
    for root, dirs, files in os.walk(folder):
        depth = len(Path(root).parts) - base
        dirs[:] = [] if depth >= MAX_DEPTH else [d for d in dirs if not d.startswith('.') and d not in SKIP_DIRS]
        for f in files:
            if f.endswith('.spider'):
                yield Path(root) / f


def strip_html(text):
    """Notes as plain text: block tags become spaces, inline ones (bold, links…) just disappear."""
    text = re.sub(r'</?(p|div|li|h\d|br|tr|td|th|blockquote|pre|hr|ul|ol|table)\b[^>]*>', ' ', text or '', flags=re.I)
    return re.sub(r'\s+', ' ', html.unescape(re.sub(r'<[^>]+>', '', text))).strip()


def summarize(p: Path):
    """Title, counts, searchable text and a lightweight copy for the thumbnail (no pictures, no notes)."""
    st = p.stat()
    key = (st.st_mtime_ns, st.st_size)
    cached = summaries.get(str(p))
    if cached and cached[0] == key:
        return cached[1]
    data = json.loads(p.read_text(encoding='utf-8'))
    if not isinstance(data, dict):
        return None
    # Version 3+ keeps bubbles under "bubbles" (several main ideas possible); older files under "nodes"
    # with bubble 0 as the one centre. The app itself upgrades files; here we only need to read them.
    key_name = 'bubbles' if isinstance(data.get('bubbles'), dict) else 'nodes'
    nodes = data.get(key_name)
    if not isinstance(nodes, dict) or not nodes or (key_name == 'nodes' and not isinstance(nodes.get('0'), dict)):
        return None
    texts, preview, with_notes = [], {}, 0
    for k, n in nodes.items():
        if not isinstance(n, dict):
            continue
        if isinstance(n.get('text'), str):
            texts.append(n['text'])
        notes = n.get('notes') if isinstance(n.get('notes'), str) else ''
        note_text = strip_html(notes)
        if note_text:
            texts.append(note_text)
        pn = {key: n[key] for key in PREVIEW_KEYS if key in n}
        if isinstance(n.get('img'), dict):
            pn['img'] = {'src': PLACEHOLDER_IMG, 'w': n['img'].get('w', 4), 'h': n['img'].get('h', 3)}
        if note_text or '<img' in notes or '<table' in notes:
            pn['notes'] = '<p>notes</p>'
            with_notes += 1
        preview[k] = pn
    if key_name == 'nodes':
        mains = [nodes['0']]
    else:
        def sort_key(item):
            k, n = item
            order = n.get('order')
            return (order if isinstance(order, (int, float)) else int(k) if str(k).isdigit() else 0, str(k))
        mains = [n for k, n in sorted(nodes.items(), key=sort_key)
                 if isinstance(n, dict) and n.get('parent') is None and n.get('kind') != 'free']
    names = [' '.join(m['text'].split()) if isinstance(m.get('text'), str) and m['text'].strip() else 'Untitled' for m in mains]
    if isinstance(data.get('title'), str) and data['title'].strip():   # the diagram's own name, if it has one
        title = ' '.join(data['title'].split())[:200]
    elif not names:
        title = p.stem
    elif len(names) <= 3:   # matches docTitle() in the app
        title = ', '.join(names[:-1]) + ' and ' + names[-1] if len(names) > 1 else names[0]
    else:
        title = f"{', '.join(names[:2])} and {len(names) - 2} more"
    links = data.get('links') if isinstance(data.get('links'), dict) else {}
    preview = {key_name: preview, 'links': links, 'settings': data.get('settings', {}), 'nextId': data.get('nextId', 1)}
    for k in ('format', 'version'):   # so the app knows which version to upgrade the thumbnail from
        if k in data:
            preview[k] = data[k]
    summary = {
        'path': str(p), 'name': p.name, 'folder': str(p.parent), 'mtime': st.st_mtime, 'bytes': st.st_size,
        'title': title, 'count': len(preview[key_name]), 'notes': with_notes, 'mains': max(1, len(mains)),
        'links': len(links), 'text': '\n'.join(texts)[:50000], 'preview': preview,
    }
    summaries[str(p)] = (key, summary)
    return summary


def library():
    with lock:
        cfg = load_config()
        paths = {}
        for folder in cfg['folders']:
            f = Path(folder)
            if f.is_dir():
                for p in scan(f):
                    paths[str(p)] = p
                    if len(paths) >= MAX_FILES:
                        break
        alive = [r for r in cfg['recent'] if Path(r).is_file()]
        if alive != cfg['recent']:   # forget recent files that have since been deleted or moved
            cfg['recent'] = alive
            save_config(cfg)
        for r in alive:
            paths.setdefault(r, Path(r))
    files = []
    for p in paths.values():
        try:
            s = summarize(p)
        except (OSError, ValueError):
            continue
        if s:
            files.append(s)
    files.sort(key=lambda s: s['mtime'], reverse=True)
    return {'folders': cfg['folders'], 'home': str(Path.home()), 'files': files}


def route(path, req):
    if path == '/api/ping':
        return {'ok': True}
    if path == '/api/open':
        p = dialog('Open spider diagram')
        if not p:
            return {'cancelled': True}
        text = p.read_text(encoding='utf-8')
        remember(p)
        return info(p, text=text)
    if path == '/api/open-path':
        p = diagram_path(req.get('path'))
        text = p.read_text(encoding='utf-8')
        remember(p)
        return info(p, text=text)
    if path == '/api/save':
        p = diagram_path(req.get('path'))
        write_atomic(p, req['data'].encode('utf-8'))
        remember(p)
        return info(p)
    if path == '/api/save-as':
        p = dialog('Save spider diagram as', save=True, suggested=req.get('suggested'))
        if not p:
            return {'cancelled': True}
        write_atomic(p, req['data'].encode('utf-8'))
        remember(p)
        return info(p)
    if path == '/api/library':
        return library()
    if path == '/api/library/add-folder':
        folder = pick('folder', 'Add a folder to your library', Path.home())
        if not folder:
            return {'cancelled': True}
        folder = str(Path(folder))   # drops the trailing slash macOS adds
        with lock:
            cfg = load_config()
            if folder not in cfg['folders']:
                cfg['folders'].append(folder)
                save_config(cfg)
        return library()
    if path == '/api/library/remove-folder':
        with lock:
            cfg = load_config()
            cfg['folders'] = [f for f in cfg['folders'] if f != req.get('path')]
            save_config(cfg)
        return library()
    if path == '/api/reveal':
        p = diagram_path(req.get('path'))
        if not p.is_file():
            raise ValueError('That file no longer exists')
        reveal(p)
        return {'ok': True}
    if path in ('/api/export', '/api/export-png'):
        kind = req.get('kind', 'png')
        if kind not in EXPORT_FILTERS:
            raise ValueError('Unknown export type')
        p = dialog('Export ' + ('PNG' if kind == 'png' else 'outline'), save=True, suggested=req.get('suggested'), kind=kind)
        if not p:
            return {'cancelled': True}
        write_atomic(p, base64.b64decode(req['data']))
        return info(p)
    if path == '/api/about':
        return about()
    if path == '/api/install':
        return {'message': install()}
    if path == '/api/update/check':
        return check_update()
    if path == '/api/update/apply':
        return apply_update()
    raise LookupError('unknown endpoint')


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def host_ok(self):
        # Blocks DNS-rebinding: the page must be addressed as localhost.
        return self.headers.get('Host') in (f'127.0.0.1:{PORT}', f'localhost:{PORT}')

    def send(self, code, body, ctype='application/json'):
        data = body if isinstance(body, bytes) else json.dumps(body).encode()
        self.send_response(code)
        self.send_header('Content-Type', ctype)
        self.send_header('Content-Length', str(len(data)))
        self.send_header('Cache-Control', 'no-store')
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        global last_seen
        if not self.host_ok():
            return self.send(403, {'error': 'forbidden'})
        if self.path.startswith('/api/alive?'):
            return self.alive()
        if self.path.split('?')[0] not in ('/', '/index.html'):
            return self.send(404, {'error': 'not found'})
        last_seen = time.time()
        html = app_html()
        html = html.replace('<!--spider-host-->', f'<script>window.SPIDER_HOST = {json.dumps({"token": TOKEN})};</script>', 1)
        self.send(200, html.encode(), 'text/html; charset=utf-8')

    def alive(self):
        """Each open tab keeps this connection open. Closing the tab (or the browser) drops it, which is
        how the launcher knows when nothing is using it any more, whatever the browser."""
        global live, closed_at
        if parse_qs(urlsplit(self.path).query).get('token') != [TOKEN]:
            return self.send(403, {'error': 'forbidden'})
        self.send_response(200)
        self.send_header('Content-Type', 'text/event-stream')
        self.send_header('Cache-Control', 'no-store')
        self.end_headers()
        with lock:
            live += 1
        try:
            while True:
                self.wfile.write(b': still here\n\n')
                self.wfile.flush()
                time.sleep(1)
        except OSError:
            pass
        finally:
            with lock:
                live -= 1
                if not live:
                    closed_at = time.time()

    def do_POST(self):
        global last_seen
        if not self.host_ok():
            return self.send(403, {'error': 'forbidden'})
        if self.headers.get('X-Spider-Token') != TOKEN:
            return self.send(403, {'error': 'forbidden'})
        last_seen = time.time()
        try:
            req = json.loads(self.rfile.read(int(self.headers.get('Content-Length') or 0)) or b'{}')
            self.send(200, route(self.path, req))
        except LookupError as e:
            self.send(404, {'error': str(e)})
        except Exception as e:
            self.send(500, {'error': str(e)})


def unpack(blob, text=True):
    data = zlib.decompress(base64.b64decode(''.join(blob)))
    return data.decode('utf-8') if text else data


def app_html():
    return unpack(EMBEDDED_HTML) if EMBEDDED_HTML else (HERE / 'index.html').read_text(encoding='utf-8')


# ---------- Linux desktop integration ----------

DATA = Path(os.environ.get('XDG_DATA_HOME') or Path.home() / '.local' / 'share')
INSTALLED = {
    'program': Path.home() / '.local' / 'bin' / 'spider-diagram',
    'desktop': DATA / 'applications' / 'spider-diagram.desktop',
    'mime': DATA / 'mime' / 'packages' / 'spider-diagram.xml',
    'icon': DATA / 'icons' / 'hicolor' / 'scalable' / 'apps' / 'spider-diagram.svg',
    'mime-icon': DATA / 'icons' / 'hicolor' / 'scalable' / 'mimetypes' / 'application-x-spider-diagram.svg',
}
MIME_XML = """<?xml version="1.0" encoding="UTF-8"?>
<mime-info xmlns="http://www.freedesktop.org/standards/shared-mime-info">
  <mime-type type="application/x-spider-diagram">
    <comment>Spider diagram</comment>
    <sub-class-of type="application/json"/>
    <icon name="application-x-spider-diagram"/>
    <glob pattern="*.spider" weight="80"/>
  </mime-type>
</mime-info>
"""


def refresh_desktop_caches():
    for cmd in (['update-mime-database', str(DATA / 'mime')], ['update-desktop-database', str(DATA / 'applications')],
                ['kbuildsycoca6'], ['kbuildsycoca5']):
        if shutil.which(cmd[0]):
            subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def install():
    if SYSTEM == 'Windows':
        return windows_install()
    if SYSTEM != 'Linux':
        raise RuntimeError('Installing is for Linux and Windows. On a Mac, just double-click spider-diagram-mac.command.')
    me, prog = Path(__file__).resolve(), INSTALLED['program']
    for p in INSTALLED.values():
        p.parent.mkdir(parents=True, exist_ok=True)
    if me != prog:
        shutil.copyfile(me, prog)
    prog.chmod(0o755)
    icon = unpack(EMBEDDED_ICON) if EMBEDDED_ICON else (HERE / 'icon.svg').read_text(encoding='utf-8')
    INSTALLED['icon'].write_text(icon, encoding='utf-8')
    INSTALLED['mime-icon'].write_text(icon, encoding='utf-8')
    # Some launchers skip an icon folder that has no index.theme; borrow the system one.
    theme = DATA / 'icons' / 'hicolor' / 'index.theme'
    if not theme.exists() and Path('/usr/share/icons/hicolor/index.theme').exists():
        theme.symlink_to('/usr/share/icons/hicolor/index.theme')
    INSTALLED['mime'].write_text(MIME_XML, encoding='utf-8')
    INSTALLED['desktop'].write_text(f"""[Desktop Entry]
Type=Application
Name=Spider Diagram
GenericName=Mind map editor
Comment=Create spider diagrams and export them as pictures or documents
Exec="{prog}" %f
Icon=spider-diagram
Terminal=false
Categories=Office;
MimeType=application/x-spider-diagram;
Keywords=mind map;mindmap;spider;diagram;brainstorm;notes;
StartupNotify=false
""", encoding='utf-8')
    refresh_desktop_caches()
    if shutil.which('xdg-mime'):
        subprocess.run(['xdg-mime', 'default', 'spider-diagram.desktop', 'application/x-spider-diagram'])
    return (f'Installed. Spider Diagram is in your app menu, .spider files open with it, and the program\n'
            f'itself is at {prog}. Remove it again with:  spider-diagram --uninstall')


# ---------- Windows: Start menu shortcut and .spider file type (current user only, no admin needed) ----------

WIN_APP_DIR = Path(os.environ.get('LOCALAPPDATA') or Path.home() / 'AppData' / 'Local') / 'Programs' / 'Spider Diagram'
WIN_SHORTCUT = Path(os.environ.get('APPDATA') or Path.home() / 'AppData' / 'Roaming') / 'Microsoft' / 'Windows' / 'Start Menu' / 'Programs' / 'Spider Diagram.lnk'
WIN_CLASSES = r'Software\Classes'
WIN_KEYS = [r'.spider', r'SpiderDiagram.File\shell\open\command', r'SpiderDiagram.File\shell\open',
            r'SpiderDiagram.File\shell', r'SpiderDiagram.File\DefaultIcon', r'SpiderDiagram.File']   # deepest first


def windows_refresh_icons():
    try:
        import ctypes
        ctypes.windll.shell32.SHChangeNotify(0x08000000, 0, None, None)   # SHCNE_ASSOCCHANGED
    except Exception:
        pass


def windows_install():
    import winreg
    WIN_APP_DIR.mkdir(parents=True, exist_ok=True)
    prog, ico, me = WIN_APP_DIR / 'Spider Diagram.cmd', WIN_APP_DIR / 'spider-diagram.ico', Path(__file__).resolve()
    if me != prog:
        shutil.copyfile(me, prog)
    ico.write_bytes(unpack(EMBEDDED_ICO, text=False) if EMBEDDED_ICO else (HERE / 'icon.ico').read_bytes())
    # Start menu shortcut, starting minimised: the app itself lives in your browser.
    script = ('$s = (New-Object -ComObject WScript.Shell).CreateShortcut($env:SD_LINK); $s.TargetPath = $env:SD_PROG; '
              '$s.IconLocation = $env:SD_ICON; $s.WindowStyle = 7; $s.Description = "Spider Diagram"; $s.Save()')
    WIN_SHORTCUT.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(['powershell', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-Command', script], check=True,
                   env={**os.environ, 'SD_LINK': str(WIN_SHORTCUT), 'SD_PROG': str(prog), 'SD_ICON': str(ico)})
    # .spider files: their own icon, and double-click opens them in Spider Diagram.
    values = {r'.spider': 'SpiderDiagram.File', r'SpiderDiagram.File': 'Spider diagram',
              r'SpiderDiagram.File\DefaultIcon': f'"{ico}"', r'SpiderDiagram.File\shell\open\command': f'"{prog}" "%1"'}
    for key, value in values.items():
        with winreg.CreateKey(winreg.HKEY_CURRENT_USER, WIN_CLASSES + '\\' + key) as k:
            winreg.SetValueEx(k, '', 0, winreg.REG_SZ, value)
    windows_refresh_icons()
    return ('Installed. Spider Diagram is in your Start menu and .spider files open with it.\n'
            f'The program itself is in {WIN_APP_DIR}. Remove it again with:  "{prog}" --uninstall')


def windows_uninstall():
    import winreg
    for key in WIN_KEYS:
        try:
            winreg.DeleteKey(winreg.HKEY_CURRENT_USER, WIN_CLASSES + '\\' + key)
        except OSError:
            pass
    WIN_SHORTCUT.unlink(missing_ok=True)
    (WIN_APP_DIR / 'spider-diagram.ico').unlink(missing_ok=True)
    windows_refresh_icons()
    # The program file may be the one running right now, so it's left for Windows to tidy away.
    print(f'Removed Spider Diagram from your Start menu and file types. You can delete {WIN_APP_DIR} too.\n'
          'Your diagrams and library settings are untouched.')


def uninstall():
    if SYSTEM == 'Windows':
        return windows_uninstall()
    for p in INSTALLED.values():
        p.unlink(missing_ok=True)
    refresh_desktop_caches()
    print('Removed Spider Diagram from your app menu. Your diagrams and library settings are untouched.')


# ---------- installing from the app, and updates ----------

def installed_program():
    return WIN_APP_DIR / 'Spider Diagram.cmd' if SYSTEM == 'Windows' else INSTALLED['program']


def shown_version():
    """The version to show. The source folder counts as a release when it's exactly the last published
    version (checked out at the release commit, with nothing changed since); otherwise it's 'dev'."""
    if EMBEDDED_HTML is not None or VERSION != 'dev':
        return VERSION
    try:
        git = lambda *a: subprocess.run(['git', '-C', str(HERE), *a], capture_output=True, text=True, timeout=5).stdout.strip()
        released = json.loads((HERE / 'dist' / 'version.json').read_text())['version']
        if git('rev-parse', 'HEAD') == git('log', '-1', '--format=%H', '--', 'dist/version.json') and not git('status', '--porcelain'):
            return released
    except Exception:
        pass
    return 'dev'


def about():
    packed = EMBEDDED_HTML is not None   # a built single-file copy (not the source folder)
    return {'version': shown_version(), 'system': SYSTEM, 'updates': bool(UPDATE_URL) and packed,
            'canInstall': packed and SYSTEM in ('Linux', 'Windows'),
            'installed': Path(__file__).resolve() == installed_program()}


def fetch(url, limit=20_000_000):
    with urlopen(Request(url, headers={'User-Agent': 'Spider Diagram/' + VERSION, 'Cache-Control': 'no-cache'}), timeout=20) as r:
        return r.read(limit)


def latest():
    return json.loads(fetch(UPDATE_URL + 'version.json?t=' + str(int(time.time())), 100_000))


def check_update():
    if not about()['updates']:
        return {'available': False}
    info = latest()
    return {'available': str(info.get('version', '')) > VERSION, 'version': info.get('version'), 'current': VERSION,
            'summary': str(info.get('summary', ''))}


RESTART = False


def apply_update():
    """Download the newest build for this computer, check it, and put it in place of this program."""
    global RESTART
    if not about()['updates']:
        raise RuntimeError('Updates are not set up for this copy')
    info = latest()
    name = 'spider-diagram-windows.cmd' if SYSTEM == 'Windows' else 'spider-diagram-linux'   # Mac uses the Linux file
    data = fetch(UPDATE_URL + name + '?v=' + str(info['version']))
    if hashlib.sha256(data).hexdigest() != info['sha256'][name]:
        raise RuntimeError('The download was damaged; nothing was changed. Try again later')
    if b'Spider Diagram launcher.' not in data[:4000]:
        raise RuntimeError("That download doesn't look like Spider Diagram; nothing was changed")
    me = Path(__file__).resolve()
    mode = me.stat().st_mode
    write_atomic(me, data)
    if SYSTEM != 'Windows':
        me.chmod(mode | 0o755)
    RESTART = True
    threading.Thread(target=lambda: (time.sleep(0.5), SERVER.shutdown()), daemon=True).start()
    return {'version': info['version']}


def restart():
    """Start the freshly updated program in place of this one (no new browser tab: the page reloads itself)."""
    me = str(Path(__file__).resolve())
    if SYSTEM == 'Windows':
        si = subprocess.STARTUPINFO()
        si.dwFlags |= subprocess.STARTF_USESHOWWINDOW
        si.wShowWindow = 7   # minimised, like the Start menu shortcut
        subprocess.Popen([sys.executable, '-x', me, '--no-browser'], creationflags=subprocess.CREATE_NEW_CONSOLE, startupinfo=si)
    else:
        os.execv(sys.executable, [sys.executable, me, '--no-browser'])


SERVER = None


def main():
    global SERVER
    args = sys.argv[1:]
    browser = '--no-browser' not in args
    args = [a for a in args if a != '--no-browser']
    if args and args[0] in ('-h', '--help'):
        return print(__doc__)
    if args and args[0] == '--install':
        try:
            return print(install())
        except RuntimeError as e:
            sys.exit(str(e))
    if args and args[0] == '--uninstall':
        return uninstall()
    url = f'http://127.0.0.1:{PORT}/'
    if args:
        url += '#open=' + quote(str(Path(args[0]).expanduser().resolve()))
    for attempt in range(1 if browser else 40):   # after an update, the old copy may still be letting go of the port
        try:
            server = SERVER = ThreadingHTTPServer(('127.0.0.1', PORT), Handler)
            break
        except OSError:
            time.sleep(0.25)
    else:
        # Already running (e.g. another window): just open another tab on it.
        if browser:
            webbrowser.open(url)
        return

    def watchdog():
        # Stops a few seconds after the last tab closes (a reload is back well within that). A tab from
        # an older version, without the connection, just checks in now and then: then it's IDLE_EXIT.
        global last_seen
        before = time.time()
        while True:
            time.sleep(1)
            now = time.time()
            if now - before > 20:   # the computer was asleep: give the tabs a chance to reconnect
                last_seen = now
            before = now
            if live:
                continue
            if (closed_at is not None and now - closed_at > 3 and last_seen < closed_at) or now - last_seen > IDLE_EXIT:
                server.shutdown()
                return

    threading.Thread(target=watchdog, daemon=True).start()
    print(f'Spider Diagram is running at {url}\nYou can minimise this window. It stops by itself a few seconds '
          'after you close the browser tab.')
    if browser:
        def open_tab():
            # A tab left open from last time reconnects by itself within a second or two: then use that
            # one rather than opening another. (Opening a file always gets a tab to open it in.)
            if not args:
                for _ in range(30):
                    time.sleep(0.1)
                    if live:
                        return
            webbrowser.open(url)
        threading.Thread(target=open_tab, daemon=True).start()
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    server.server_close()
    if RESTART:
        restart()


if __name__ == '__main__':
    main()
