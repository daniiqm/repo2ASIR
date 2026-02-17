#!/bin/bash

# Práctica 7.1 - Daniel

FICHERO="usuarios.csv"
EMPRESA="Secure Ayelo"
OFICINA="Ayelo de Malferit"
DIR_TMP="/tmp/ASO"
LOG="errores_alta.log"

OK=0
ERR=0

if [ "$UID" -ne 0 ]; then
    echo "ERROR: Este script debe ejecutarse como root."
    echo "$(date '+%F %T') - ERROR: Script ejecutado sin ser root." >> "$LOG"
    exit 1
fi

if [ ! -f "$FICHERO" ]; then
    echo "ERROR: No se encuentra el fichero $FICHERO"
    echo "$(date '+%F %T') - ERROR: No se encuentra el fichero $FICHERO" >> "$LOG"
    exit 2
fi

if [ "$(wc -l < "$FICHERO")" -le 1 ]; then
    echo "ERROR: El fichero $FICHERO no contiene datos de usuarios."
    echo "$(date '+%F %T') - ERROR: El fichero $FICHERO no contiene datos de usuarios." >> "$LOG"
    exit 3
fi

mkdir -p "$DIR_TMP"


tail -n +2 "$FICHERO" | while IFS=';' read login apellido2 apellido1 nombre dni movil fijo calle localidad cp provincia correo puesto departamento
do
    echo "=== Procesando usuario $login ==="

    # Comprobar si el usuario ya existe
    wbinfo -i "$login" &> /dev/null
    if [ $? -eq 0 ]; then
        echo "Usuario $login ya existe. No se da de alta."
        echo "$(date '+%F %T') - AVISO: Usuario $login ya existe. No se da de alta." >> "$LOG"
        ERR=$((ERR+1))
        continue
    fi

    contra=$(echo "$dni" | tr '[:upper:]' '[:lower:]')

    # 1) Alta del usuario
    samba-tool user create "$login" "$contra" \
        --given-name="$nombre" \
        --surname="$apellido1 $apellido2" \
        --department="$departamento" \
        --mail-address="$correo" \
        --job-title="$puesto" \
        --company="$EMPRESA" \
        --physical-delivery-office="$OFICINA" \
        --must-change-at-next-login

    if [ $? -ne 0 ]; then
        echo "ERROR: No se pudo crear el usuario $login"
        echo "$(date '+%F %T') - ERROR: Fallo al crear usuario $login" >> "$LOG"
        ERR=$((ERR+1))
        continue
    fi

    # Obtener DN real del usuario
    dn_real=$(samba-tool user show "$login" | grep "^dn:" | cut -d' ' -f2-)

    if [ -z "$dn_real" ]; then
        echo "ERROR: No se pudo obtener el DN de $login"
        echo "$(date '+%F %T') - ERROR: No se pudo obtener DN de $login" >> "$LOG"
        ERR=$((ERR+1))
        continue
    fi

    # 2) Generar LDIF
    fileldif="$DIR_TMP/$login.ldif"

    cat <<EOF > "$fileldif"
dn: $dn_real
changetype: modify
add: mobile
mobile: $movil
-
add: homePhone
homePhone: $fijo
-
add: streetAddress
streetAddress: $calle
-
add: l
l: $localidad
-
add: postalCode
postalCode: $cp
-
add: st
st: $provincia
-
add: c
c: ES
-
replace: countryCode
countryCode: 724
-
add: co
co: España
-
add: employeeID
employeeID: $dni
EOF

    # 3) Aplicar LDIF
    ldbmodify -H /var/lib/samba/private/sam.ldb "$fileldif" &> /dev/null
    if [ $? -ne 0 ]; then
        echo "ERROR: No se pudieron modificar los atributos de $login"
        echo "$(date '+%F %T') - ERROR: Fallo al modificar atributos de $login" >> "$LOG"
        ERR=$((ERR+1))
        rm -f "$fileldif"
        continue
    fi

    rm -f "$fileldif"

    echo "Usuario $login dado de alta y modificado correctamente."
    OK=$((OK+1))
done

# --- Resumen final ---
echo "Usuarios dados de alta correctamente: $OK"
echo "Usuarios con errores: $ERR"

echo "$(date '+%F %T') - INFO: Usuarios dados de alta correctamente: $OK" >> "$LOG"
echo "$(date '+%F %T') - INFO: Usuarios con errores: $ERR" >> "$LOG"
