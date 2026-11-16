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
    '/dZUUWFu1eqgPzc/B7GShnhKICQQZ3RppZ4lELaxxcVsQIcuCcQiu5fL1Sogak3V1KYGW04YANCRMmy/JujSslxtaZ8cAN9OFKKT'
    'nN5JUQiO+Igc6qBGMryMNKM0sgSbeWOKRFCpKWUYEKxKC2h3Va2JexOWqgyUHOhJXanVlVZrGY4vssBZo0EEHsDu41jW0HHpK3OX'
    'efbMwbeuHpj16lal9Vyptts/bl6eTq4H7Z32jzb8gs/2XqU6OHq8ubvYe1B2bm7lp5Pb/Tt4tw8Fjo7b9M+Pabu9E3ad69ndi7F7'
    'fDB8urfaR9Ae1N9nRdo7w0ftYtpe5R/ouxU+0if0f3v2o/07/GO/PD1cPOO3Jv7ZvZ7dH9g6AnZA4F070e9T9tuKfl+x35pxtCPj'
    'tzv2e9Y5ONnDb0/U3tDJ/LYyv597RydUn4DYewu7R53nBD6ap/On+1rnjmZpgH967aPz9t1g56i9f/J433EHUeluHaZ+71nBll7Y'
    'fEfzbI1gvsLqHfak4xiOo1e7N1j/agh/wqCVai813w87w95oP1kMqPk0gvdXpw58v7iHR/stfOx1E/h3Fo9nt83Gs99rd6c7k/Yh'
    'fLZ3bHx+82Nn3D48b58NYNB7x+3zdvutvdetqNMdmL+7vR1EtundPnwe7Py4O9yZTo93pr2jnWnzbHf6cr7/o3mzP9y/2r/evz0Y'
    'Th/2337oB9f714e7+4+HQ9k4emv299961snusXmyMzWP3hqs7R930F4P2qse77ar5sHO/t3RsGr+3P+NCgz3ere9N23fD/baNzD7'
    'QwD9bX+n0vzRPpzS3oK+4Vnqn/P9nR+PR+3BUeWt3d7cx70z/QFlfwB8d8ftaOdcHwzbg/P9/cHd4fHtwXXv7mB3oANiXp9b5+rJ'
    '7KW7f3eyd3IzGPTuj+WL/Zfx0duddjXFvgGJcD8esL0r/rO/C30d7Ax6x1juYgjvB/sA4w+Y4/P9uO8dqD8gOG+g7527+4O3wdPh'
    'cOcN+vaPrqs3VzvNnR/35/LJbTA5qqgDWMrpPo5/b/9Hu9K+9JRD73rwVj99f/f2W9evd4/nh/u39HD6eH11p9uHezvD/9xvftw9'
    '7p8fe68XN6Ng7353aN+c1J/vPL+tDM6PHf64PbVMVznVpxePe7v/678fwOu9k+trd+/HHczIzSzcVwcXO7d3+nD4n+JbRT89fa2/'
    'eJ5373UaL9dHd7PNq6k/7vZvFP1Gf7Ubr3eX42rjOejuuLryw1I2R+Fdo3N5pY7U2dvF7rPWe5toT7W7N9kI3uX+/a2pX7sXlbsn'
    'bWK7z96mdt9TrOaO8/By8zoejWYOCM792fnM8Yz7zXB0bL11+1Xnpt0czSb6lW/XPbVedZ9frdFJZbr7fqkEjVPd6A47d+8d7f2q'
    'cVwzW/L7y53b8o9DZfp6dtt879Sco9r98WTz6unVu918ulSu3i+bVzPob2zrev3u1XuYXN813s9lTR3VvUf/efPVOrOvbqfaU/Pk'
    'eVg/eD5Tr6cN+6p+/n595Rz5b63b9xCWzTh4f9g9ub7tvDwaV49Ot9NtnvyQL73GmTseP46CavOhqftD+e3q8qTuPW9en0zNvqdU'
    '2uPNxuRau5VvtWjCR9WngTuSd9xT/fnu/Fj81vZedw/379gu/wFY8u+/X2FBh/orYMK10rm/3ms8qle34fBscuzdvRp2eDHp1vfa'
    'ysPdqXE1bYw7nZlrPTU2X68OzZ2Xqnlx2em7wVslPL1ovd0fXQ8fw4tw/9Yw1bB/cHvavrIfzmaN8VPfn2ie0bkbP109nR2MYPEt'
    'rTu8PgIi+TarIxe1N91g57x/fNPqerpmtHbN4e3r3n7NmtqVZz88u3w9CZzRULl8U8NOvfNqj73KzsP5nXKt3sqb+81+sy3Lm+Pq'
    'wWV3qPyYWF71TXtrvT8bNNL+7d7VyV0+ddoZHlxQobtz/z+APt4axpnshS8d0369q9wpZ4dKvfd64xyP5bO6claxK2rPC99uOw/u'
    '5fXB1cX11fDg7vbK7TpP9UdgEMp5ayK/aIP21Wjauuec5/X69LVzbdbuHo/eXjpe961h65v+zas9e7/u9MZ38l2vNjp+npx27bs7'
    '+R2WdVDVCKQjRX5/O8kD+OCw/chI2uPFzg9O0vA3lNLb8sHh4AIKXGAB+Lkz/Hd9v6seGA9HM/1s4l6b2uzKhuf3PcCzWfeiM6rt'
    'ea/WozN2Bg9nndmr8nBgnDcfbedOfrU7p51j353og4vO2+WjfXryrHWerjoP1UPlanT1EO5P6he28thSL482g9b+m1Lpv760dLlx'
    'FdaU0Vl4dOU9v7602/IbCnttRbvUWufG2cVp5d5vVNq759rJRH5seXpdab60Tp2rp4PZuGK+jjut+ma1tavuqMb4afx0O9IeK7fh'
    'rNrQ3drZuPZeOzpv3Oje7bN68lY/2bz05efm6BKpx0Vb39Nsxzk9Cdv67vOPwwEnK/ACOFH3BzyDT3xBfMoFcbcb/YgoEGNV2ABn'
    'YP+xJXZG1VG/Fx7bB28HvtuqH15gIWXT0x8s3Xlqvdt3153b+pt2+z6Y9R7OJo+2WXl6vRvVwyfzqtfwrePJsKMeyJ2Da/j/0lQG'
    '+tQ0nx6Cydtr3XmcvN8edc6vO5utE7nl62rjdnd8Xx2Zs86mPKr4Y7W+b47HI+f9btp8fukauxf6tV6fHI1/KAj53rlcUfV6/1l5'
    'e3hR3nsP183APO1teo8z4zUY1Q4bumc5irNptifamV2fmNXX10kdcJQG29oLVN+wrDNjPDr2nu393vGgNhq/vtY6F0gV4xnarc44'
    'p77f8SN0x6HQJoBvOy+uO33E/3BRd6znncH0P/9n253u7dJan54fnh52jh3Cy+mjDRTw8TA4YLTwf/FvO9eDH2zbvSJqHz7s3yDh'
    'uifCdQIr2WGEawTr2yHChe/3e+8v53t7/ZY3a1x4d62OLquVs8nFld16aN7qjbPTh2DYH8vnzuTxrav2n++vmu2Th33z6mi2e9GE'
    'ni7PZ2YYDDsVo3moXFcap/Zr5fr5oXbU6Z9r5mzU6gZea6Y6bz3FeNdvd93N+ydn/Nxwu179EOpfnZ85F83JQ+VgdvnDqepq5cdb'
    'Y9R3Hq5CoF5+5cB4faiOTjph5+m51u1t9vaMqw4iae103Hl5fT57ebAr/t1d7fL2xpdrB8pB886/CyvTHUWuNNsH9coAepKxp9P6'
    '5W3t9Hlz7+XcuzptdZrvJ0HrR/NdrwzfG1bl+fp0ovwYy93O/cmmbj02J9MLuXUGs3TUVi+Dy47brd84R2OvVR9O5DvVPFFCvfMy'
    'ax6+Om+vYed4Mn6ojQxdHU67zq7uPU+eG+ddT0Gqo1yeKFdT9cfs7MV/en2QH/TOrdbSJhdvT+N7X9l9OLuYWbUfE/+uc/xqVlXb'
    'OQ20qjEenzS8XWIouHwHtez6LVvfn3wPzw73+zgAP6Llt/Rj5/XysT6s+s+ndqj5mmzXLjcVfTO8c5z6PvCbydPB+P128nBqH+n7'
    '3RP3/OGqtrczPb0IJifh/fhN9u79+mzzxqg7e703pT87fHyVH52Go2/WfcVv9K8be87pK/xjw//3r56pdDqmcuucT3Rdu75sPHr9'
    '7tXu1ZnTahv+7OFeebUP3Grl4NV/2DQb6gk0Xam5vcbs6O7qrOZ7vVndN3aBom+6zrjRaXmv017tpR7ataN3ZTZ+vdxvQ3c+/Ou2'
    'L3pZe9TdWxPwQ2moZ8pM6VTlzqm1WR3tPr6ORg/ty0G18tqwe0+v3Zn81Nk1rfDwtXJxZdXkyaHx0Huwz/y+9nZambTCq5rXvL+6'
    'HHS7h8r7+dvmYWtyrdy+tcxHkE07xrjRvanpvje+O9M6d6/1s8ZtQ9+bnYGM/97brdrv+7Ou7fVvrLNWp39xWbt93Typa9f1bv+k'
    'qj2B7nKvNPX+iyePT8KjZ8080KpPzWpzarwg/j/vzJq3l4Fnvp21DurPb97DuCm3jsLz5/u9vqzIyvXkblbdPQFOvjtGfnDPcMQA'
    'MsMx44FxBsIXxhk+WuLo0rgz7tTLK+3t/Oi+ZZ+osLB+96HqH1V+XFy91FvWY+td672fvx/d7b2qF933h4ue8XawV+s0KvudIy+8'
    'M0J98102dee09aPVfei+Ko+V/Ttfdxv2RPFaT/2Tq+uar25ev8HSjhu91/HDaf21XrfNV9DKOh379qG2CYw6lB8rh+bErZycz4yd'
    '90lnctwb2B3nqGKcG+bb68Hm5O5F6Z9M9F59ovuv7Z798nShnbxqjfD2ZdBuB0vsmOGwdn871F4mj+Hm+L13q7wePDb2hub44Pq0'
    '+3CqXkyuWxf6bQiIMascV18On6ynzWvrptG5aVw+z3YaV4On8Ymj3k0ezevu5M609U7jrik35Jb3cm6eVtXrl8dQORtfmON7XW7p'
    'lnf3oB3dNm+VN6dav1ObdeXalk/qs37H77YOLr23C++s09+tHDauHt6fQUY8OLFu5YvBmzc+r/vVhwvdaXmVJ9/a9Pq3D0Siaj/C'
    'C+O0c3cK4qpbP3V0a7QZ1C5eK3uhcn3V6xxNp49oYmkSzx25CohUwSFXM+nVD3zzfFi7si8vqzMbSNtpqNoPY+8hfH1QT1TnqPmu'
    'gJ4XdnwrME73G3ebo7Fb39TvKheV42nPv2t2D55bN/6zcv1+7AyM4ezSGDaNx83Re8+y3q/rRw1luN9QLtv15/p41mt0j6YXQffw'
    'Ibj3Kr7iNfeHew70OjvXjl9n56+tB2OsGK3OTaVy/rJ/+xL+UOqtl7eLg0lV79/3a+rB+azd1pnpbVOv18+MS8UwLk7N09fpTqs9'
    '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'
    'gj/yv28TjzO8YNcEfOlfGssBFh/FeBt9FyF94blKnKnIc23hSqp65ftIgoePVIGmui4N4gWkGdZIQrJMqso6NJ2GTQ4jsTYH6xmJ'
    'vbNNQ12o8bTVB5RjMR+YTTSJALysWC2QdDzvArTODo9Yi14N0YqjrBHR0ZNncUFPcywtvHSZstDwpuzQSuMPrfbq07WnTOCuPvr9'
    '6hMXFCNFujSqv5aPiPde7Xyfj/yxiHB9o0FhBaDL4XPVHWaH7C0MRec7rmAFQ+4aC9C6gnVsgC1WP+CkbTyCg2zCnmswu1hCLI0f'
    'aPhvkwy+l+ZIYFS4wDlIZJfdcwnhrgEXWCunr1UTCpAhLDTEVsjCw/JQ5aC/xPlPNHhUwUt6Z86w1hU/GPX9UwOzwAzunVlzkdvR'
    'kB49WSFQdhoKdSZ5qiz9IgqYLKiwxNY+VCPFpVlGNZoRCgbz3aGrwvbJ1tDwOf/DytoTM+5zopaiXlaeI47li8cY51E+Kr7BGZEQ'
    'FCpMhpccy91MiImqJBYSEnXR+DA7dQZ8rtQnpiHEbNQLOWEpC8hsOcB5INJlZZn0YogJJiO4nRsnE5oi8o+32URs78hwavYu3OMa'
    'teyN13AwwTtRtQxcJ7YPqBIh9MvYM1LzHSoASHhcwhFZiiplwdzCuiwfJ28u0xMq//HDD8v/6ePWD5KvbTyipkpkXODgtSyAddgE'
    'PRDlVShzBKu0pCkFM7tt+emXH4yM7igUHHsV99u4Ag5QPVQQmKpi9w+bueVnwFpUemMh3v/rwsFisrB8lIT2PWaoiBTDXvvzjC7z'
    '00qgAHqjUQLoX1NW4uIYr3/n9O+5L9eNgHAexMZn+a8Oq3wBWlFjRAzMwy9hMUI2m9WCjIA0H6oVe3njlGR4F2Xdludevv+e5z/N'
    'cpQSJKVDzlUc+P+7b5KD2HMPqAUACDzuxeEeGe5k5HClNxFafFf6dV03XpiqSZDdWmJvsTBgVxmxdy09ITI8pT7Ou9XJsKKkOgnL'
    'DRhNI9InEr9CLOOEzkQu+QLFdn6quno5TUIWcy7afCopDRWrfOSYbKFTyYXnUsI2Ip0+OxNeiEaDCLM3Y3gI04VS9HMivmk5i/Ew'
    'LRbo1fGLUVF51S+85+XnQcs9r9le5Vvufcsr3wrvGySoJ1mlADChV4aVbYapXPn+yaNXq9Wh4O7RGrg2rRrSsaJOU8d/nZ6uf5mO'
    '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'
    '5BdEN/x7ujqfPbj2f8M9gzE='
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
VERSION = '2026.11.16.1838'        # build.py stamps each build with its date and time, e.g. 2026.10.19.1534
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
