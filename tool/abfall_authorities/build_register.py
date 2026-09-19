"""Destatis Gemeindeverzeichnis (gv.xlsx) -> register.json.

Every county (Kreis / kreisfreie Stadt) and every municipality with its
official key (ARS), population and postcode. The first five digits of a
municipality's key name its county, which is what the authority research
starts from. Source: destatis.de, AuszugGV2QAktuell.xlsx, Gebietsstand 30.06.2026.
"""
import json, openpyxl

STATES = {'01':'Schleswig-Holstein','02':'Hamburg','03':'Niedersachsen','04':'Bremen','05':'Nordrhein-Westfalen','06':'Hessen','07':'Rheinland-Pfalz','08':'Baden-Württemberg','09':'Bayern','10':'Saarland','11':'Berlin','12':'Brandenburg','13':'Mecklenburg-Vorpommern','14':'Sachsen','15':'Sachsen-Anhalt','16':'Thüringen'}
KREIS_KIND = {'41':'kreisfreie Stadt','42':'Stadtkreis','43':'Kreis','44':'Landkreis','45':'Regionalverband'}

wb = openpyxl.load_workbook('gv.xlsx', read_only=True)
ws = wb[wb.sheetnames[1]]
kreise, gemeinden = {}, []
for r in ws.iter_rows(values_only=True):
    sa = r[0]
    if sa == '40':
        key = r[2] + r[3] + r[4]
        kreise[key] = {'key': key, 'name': r[7], 'kind': KREIS_KIND.get(r[1], r[1]), 'state': STATES[r[2]], 'population': 0, 'municipalities': 0}
    elif sa == '60':
        kkey = r[2] + r[3] + r[4]
        if kkey not in kreise: continue  # the uninhabited German-Luxembourg condominium
        pop = int(r[9] or 0)
        gemeinden.append({'ars': kkey + r[5] + r[6], 'kreis': kkey, 'name': r[7], 'population': pop, 'plz': r[13] or None})
        kreise[kkey]['population'] += pop
        kreise[kkey]['municipalities'] += 1

json.dump({'source': 'Destatis Gemeindeverzeichnis, Gebietsstand 30.06.2026', 'kreise': list(kreise.values()), 'gemeinden': gemeinden}, open('register.json', 'w'), ensure_ascii=False, indent=1)
print(len(kreise), 'Kreise,', len(gemeinden), 'Gemeinden,', sum(g['population'] for g in gemeinden), 'people')
from collections import Counter
print(Counter(k['state'] for k in kreise.values()))
