
let refreshStatusInterval = null;
let refreshTelemetryInterval = null;
let refreshSystemStatusInterval = null;
let refreshProtocolInterval = null;
let currentMode = "ATLAS";

function switchView(viewName)
{
    document.querySelectorAll('.page-view').forEach(el => el.style.display = 'none');
    document.querySelectorAll('.sidebar a').forEach(el => el.classList.remove('active'));

    const witsMenu = document.getElementById('menu_wits');
    if (witsMenu) {
        witsMenu.style.display = 'block';
    }

    let el = document.getElementById('view_' + viewName);
    if (el) {
        el.style.display = 'block';
    } else {
        console.warn("Ошибка: не найден блок страницы с ID: view_" + viewName);
    }

    el = document.getElementById('menu_' + viewName);
    if (el) {
        el.classList.add('active');
    } else {
        console.warn("Ошибка: не найден элемент меню с ID: menu_" + viewName);
    }

    clearInterval(refreshStatusInterval);
    clearInterval(refreshTelemetryInterval);
    clearInterval(refreshSystemStatusInterval);
    clearInterval(refreshProtocolInterval);

    if (viewName === 'status') {
        loadStatus();
        refreshStatusInterval = setInterval(loadStatus, 5000);
    } else if (viewName === 'config') {
        toggleConfigMode('edit');
    } else if (viewName === 'adccfg') {
        loadADCConfig();
    } else if (viewName === 'wits') {
        loadWitsConfig();
    } else if (viewName === 'setup') {
        const viewMode = document.getElementById('setup_view_mode');
        const editMode = document.getElementById('setup_edit_mode');
        const btnEdit = document.getElementById('btn_setup_edit');
        if (viewMode) viewMode.style.display = 'block';
        if (editMode) editMode.style.display = 'none';
        if (btnEdit) btnEdit.style.display = 'inline-block';
        loadSystemSetup();
        refreshSystemStatusInterval = setInterval(loadSystemSetup, 10000);
    } else if (viewName === 'telemetry') {
        loadTelemetry();
        refreshTelemetryInterval = setInterval(loadTelemetry, 1000);
    } else if (viewName === 'protocol') {
        loadProtocol();
        refreshProtocolInterval = setInterval(loadProtocol, 10000);
    } else if (viewName === 'updates') {
        loadVersions();
    } else {
        console.info('505: unregistered view name: ' + viewName);
    }
}

function toggleConfigMode(mode)
{
      if (mode === 'edit') {
          document.getElementById('sub_config_show').style.display = 'none';

          if (currentMode === 'ATLAS') {
              document.getElementById('configFormAtlas').style.display = 'block';
              document.getElementById('configFormSIU').style.display = 'none';
          } else {
              document.getElementById('configFormSIU').style.display = 'block';
              document.getElementById('configFormAtlas').style.display = 'none';
          }

          document.getElementById('sub_config_edit').style.display = 'block';
          loadAndParseConfigToInputs();
      } else {
          document.getElementById('sub_config_edit').style.display = 'none';
          document.getElementById('sub_config_show').style.display = 'block';
          loadConfigFiles();
      }
}

function triggerAction(actionUrl) {
      if (actionUrl === 'api_action_reboot' && !confirm("Перезагрузить устройство?")) {
          return;
      }

      if (actionUrl) {
          const el = document.getElementById('lbl_status');
          el.style.backgroundColor = '#fff3cd'; /* Мягкий желтый цвет предупреждения */
          el.style.color = '#856404';
          el.style.borderColor = '#ffeeba';

          if (actionUrl === 'api_action_restart') {
              el.innerText = 'Перезапуск...';
          } else if (actionUrl === 'api_action_start') {
              el.innerText = 'Запуск...';
          } else if (actionUrl === 'api_action_stop') {
              el.innerText = 'Остановка...';
          } else {
              el.innerText = 'WAIT';
          }
          const el2 = document.getElementById('lbl_status2');
          if (el2) {
            el2.innerText = el.innerText;
            el2.style.backgroundColor = el.style.backgroundColor;
            el2.style.color = el.style.color;
            el2.style.borderColor = el.style.borderColor;
          }
      }
 
      if (actionUrl !== 'api_action_reboot') {
          message("Действие выполняется...", 3000);
      }

      fetch('?' + actionUrl)
          .then(response => response.text())
          .then(result => {
              const status = result.trim();
              if (status === 'REBOOTING') {
                  style="background: #fff3cd; color: #856404; border: 1px solid #ffeeba;"
                  message("Система уходит в перезагрузку\n\nСтраница обновится автоматически\nчерез 25 секунд", "info", 25000, style);
                  setTimeout(() => window.location.reload(), 25000);
              } else if (status === 'ERR_500') {
                  message("Системная ошибка\n\n500 Internal Server Error\n[" + status + "]", "error");
              } else {
                  loadStatus();
              }
          })
         .catch(err => {
             msg = "Ошибка: нет ответа";
             console.error("AJAX: " + msg + ": ", err);
             message(msg + "\n[" + err.message + "]", "error", 15000);
         })
}

function loadStatus()
{
  fetch('?api_get_status')
        .then(response => {
            if (!response.ok) {
                throw new Error("Системная ошибка\n\n500 Internal Server Error\n\n" + response.status);
            }
            return response.json();
        })
        .then(data => {
            currentMode = data.mode;
            document.getElementById('lbl_time').innerHTML   = data.time;
            document.getElementById('lbl_uptime').innerText = data.uptime;
            document.getElementById('lbl_serial').innerText = data.serial;
            document.getElementById('lbl_ip').innerText     = data.ipadr;
            document.getElementById('lbl_app').innerText    = data.appver;
            document.getElementById('lbl_system').innerHTML = data.system + '<br>' + data.osname;
            document.getElementById('lbl_fmwver').innerHTML = data.fmwver;
            document.getElementById('lbl_tasks').innerHTML  = data.tasks || "Нет активных процессов";
            document.getElementById('lbl_cfg_name').innerText = data.cfgname;
            document.getElementById('lbl_systemip').innerText = 'IP: ' + data.ipadr;

            const btnStartRestart = document.getElementById('btn_start_restart');
            const el = document.getElementById('lbl_status');
            el.innerText = data.status;
            if (data.status === 'RUN') {
                el.style.backgroundColor = '#e2f0d9';
                el.style.color = '#155724';
                el.style.borderColor = '#c3e6cb';
                btnStartRestart.innerText = 'Перезапустить';
                btnStartRestart.setAttribute('onclick', "triggerAction('api_action_restart')");
                btnStartRestart.style.backgroundColor = '#17a2b8'; /* цвет сине-зеленый */
                btnStartRestart.style.borderColor = '#117a8b';
            } else {
                el.style.backgroundColor = '#f8d7da';
                el.style.color = '#721c24';
                el.style.borderColor = '#f5c6cb';
                btnStartRestart.innerText = 'Запустить';
                btnStartRestart.setAttribute('onclick', "triggerAction('api_action_start')");
                btnStartRestart.style.backgroundColor = '#007bff'; /* стандартный синий цвет */
                btnStartRestart.style.borderColor = '#0069d9';
            }
            const el2 = document.getElementById('lbl_status2');
            if (el2) {
                el2.innerText = el.innerText;
                el2.style.backgroundColor = el.style.backgroundColor;
                el2.style.color = el.style.color;
                el2.style.borderColor = el.style.borderColor;
            }
      })
      .catch(err => {
          msg = "Ошибка: нет ответа";
          console.error("AJAX: " + msg + ": ", err);
          message(msg + "\n[" + err.message + "]", "error", 15000);
      })
}

// Запрос для получения версий
function loadVersions()
{
    const app = document.getElementById('version_app');
    const wcp = document.getElementById('version_wcp');
    const fmw = document.getElementById('version_fmw');
    if (!app || !wcp || !fmw) return;

    app.classList.add('version-loading');
    wcp.classList.add('version-loading');
    fmw.classList.add('version-loading');

    fetch("?action=api_get_versions")
        .then(response => {
            if (!response.ok) {
                throw new Error("Системная ошибка\n\n500 Internal Server Error\n\n" + response.status);
            }
            return response.json();
        })
        .then(data => {
            app.innerHTML = data.app_ver ? data.app_ver : "-";
            wcp.innerHTML = data.wcp_ver ? data.wcp_ver : "-";
            fmw.innerHTML = data.fmw_ver ? data.fmw_ver : "-";
        })
        .catch(err => {
            console.error("Не удалось определить версии: ", err);
            const errMsg = "<span style='color: red;'>[ошибка: " + err + "]</span>";
            app.innerHTML = errMsg;
            wcp.innerHTML = errMsg;
            fmw.innerHTML = errMsg;
        })
        .finally(() => {
            app.classList.remove('version-loading');
            wcp.classList.remove('version-loading');
            fmw.classList.remove('version-loading');
        });
}

// Загрузка текущих данных системных настроек
function loadSystemSetup()
{
    fetch('?api_get_setup')
        .then(response => {
            if (!response.ok) {
                throw new Error("Системная ошибка\n\n500 Internal Server Error\n\n" + response.status);
            }
            return response.json();
        })
        .then(data => {
            document.getElementById('lbl_setup_ip').innerText   = data.ip   || '—';
            document.getElementById('lbl_setup_gw').innerText   = data.gw   || '—';
            document.getElementById('lbl_setup_mac').innerText  = data.mac  || '—';
            document.getElementById('lbl_setup_ssh').innerText  = data.ssh  || '—';
            document.getElementById('lbl_setup_ftp').innerText  = data.ftp  || '—';
            document.getElementById('lbl_setup_http').innerText = data.http || '—';
            document.getElementById('lbl_setup_lang').innerText = data.lang || '—';
            document.getElementById('lbl_setup_sno').innerText  = data.sno  || '—';
        })
        .catch(err => {
            msg = "Ошибка: нет ответа";
            console.error("AJAX: " + msg + ": ", err);
            message(msg + "\n[" + err.message + "]", "error", 15000);
        })
}

function loadConfigFiles()
{
    fetch('?api_get_config_files')
        .then(response => response.text())
        .then(data => {
            document.getElementById('file_config').innerText = data || '';
        })
        .catch(err => {
            msg = "Ошибка: нет ответа";
            console.error("AJAX: " + msg + ": ", err);
            message(msg + "\n[" + err.message + "]", "error", 15000);
        })
}

function loadTelemetry()
{
    fetch('?api_get_telemetry')
        .then(response => {
            if (!response.ok) {
                throw new Error("Системная ошибка\n\n500 Internal Server Error\n\n" + response.status);
            }
            return response.json();
        })
        .then(data => {
            document.getElementById('fld_uptime2' ).innerHTML = data.uptime ? data.uptime   : "-";
            document.getElementById('fld_enc1'    ).innerHTML = data.enc1   ? data.enc1     : "-";
            document.getElementById('fld_enc2'    ).innerHTML = data.enc2   ? data.enc2     : "-";

            str1 = ["-", "-", "-", "-"];
            str2 = ["-", "-", "-", "-"];
            str3 = ["-", "-", "-", "-"];

            str1[0] = data.ch1avrg  ? data.ch1avrg  : "-";
            str2[0] = data.ch1avrgv ? data.ch1avrgv : "-";
            str3[0] = data.ch1avrgp ? data.ch1avrgp : "-";

            str1[1] = data.ch2avrg  ? data.ch2avrg  : "-";
            str2[1] = data.ch2avrgv ? data.ch2avrgv : "-";
            str3[1] = data.ch2avrgp ? data.ch2avrgp : "-";

            str1[2] = data.ch3avrg  ? data.ch3avrg  : "-";
            str2[2] = data.ch3avrgv ? data.ch3avrgv : "-";
            str3[2] = data.ch3avrgp ? data.ch3avrgp : "-";

            str1[3] = data.ch4avrg  ? data.ch4avrg  : "-";
            str2[3] = data.ch4avrgv ? data.ch4avrgv : "-";
            str3[3] = data.ch4avrgp ? data.ch4avrgp : "-";

            const ln1 = Math.max(...str1.map(str => str.length)); 

            str1 = str1.map(str => {
              return str.padStart(ln1, '\u00A0');
            });

            const ln2 = Math.max(...str2.map(str => str.length)); 
            str2 = str2.map(str => {
              return str.padStart(ln2, '\u00A0');
            });

            const ln3 = Math.max(...str3.map(str => str.length)); 
            str3 = str3.map(str => {
              return str.padStart(ln3, '\u00A0');
            });

            document.getElementById('fld_ch1avrgv' ).innerHTML = str1[0] + " &nbsp; " + str2[0] + "&nbsp; " + str3[0];
            document.getElementById('fld_ch2avrgv' ).innerHTML = str1[1] + " &nbsp; " + str2[1] + "&nbsp; " + str3[1];
            document.getElementById('fld_ch3avrgv' ).innerHTML = str1[2] + " &nbsp; " + str2[2] + "&nbsp; " + str3[2];
            document.getElementById('fld_ch4avrgv' ).innerHTML = str1[3] + " &nbsp; " + str2[3] + "&nbsp; " + str3[3];

            document.getElementById('fld_sentok'  ).innerHTML = data.sentok   ? data.sentok   : "-";
            document.getElementById('fld_senterr' ).innerHTML = data.senterr  ? data.senterr  : "-";
            document.getElementById('fld_witsok'  ).innerHTML = data.witsok   ? data.witsok   : "-";
            document.getElementById('fld_witserr' ).innerHTML = data.witserr  ? data.witserr  : "-";
            document.getElementById('fld_dptdelay').innerHTML = data.dptdelay ? data.dptdelay : "-";
            document.getElementById('fld_swapch12').innerHTML = data.swapch12 ? data.swapch12 : "-";

            // console.log(JSON.stringify(data));

            for (let i = 1; i <= 3; i++) {
                // Безопасно очищаем входящую строку от системных переносов строк (\r, \n), если они там есть
                const raw = data['send' + i] ? data['send' + i].replace(/[\r\n]+/g, '') : '';

                if (raw) {
                    const arr = raw.split(';');

                    //
                    const fill_field_func = (id, value, isError) => {
                        const field = document.getElementById(id);
                        if (field) {
                            field.innerHTML = value.trim();
                            field.style.color = isError ? '#d32f2f' : '#888888';
                        }
                    };

                    //
                    const parse_error_func = (ipaddr, port_idx, msg_idx) => {
                        const port = arr[port_idx] ? arr[port_idx].trim() : '';
                        const msg  = arr[msg_idx]  ? arr[msg_idx].trim()  : '';

                        if (!msg) {
                            if (ipaddr) {
                                return { text: `${port}:ok`, isError: false };
                            }
                            return { text: '', isError: false };
                        }

                        if (port) {
                            return { text: `${port}:${msg}`, isError: true };
                        }
                        return { text: msg, isError: true };
                    };

                    //
                    const ip_addr = arr[0] || '';
                    const field = document.getElementById(`fld_addr${i}`);
                    if (field) {
                        field.innerHTML = ip_addr.trim();
                        field.style.color = '';
                    }

                    const err1 = parse_error_func(ip_addr, 1, 2);
                    fill_field_func(`fld_err${i}1`, err1.text, err1.isError);

                    const err2 = parse_error_func(ip_addr, 3, 4);
                    fill_field_func(`fld_err${i}2`, err2.text, err2.isError);
                }
            }

        })
        .catch(err => {
            document.getElementById('fld_uptime2' ).innerHTML = "-";
            document.getElementById('fld_enc1'    ).innerHTML = "-";
            document.getElementById('fld_enc2'    ).innerHTML = "-";
            document.getElementById('fld_ch1avrgv').innerHTML = "-";
            document.getElementById('fld_ch2avrgv').innerHTML = "-";
            document.getElementById('fld_ch3avrgv').innerHTML = "-";
            document.getElementById('fld_ch4avrgv').innerHTML = "-";
            document.getElementById('fld_sentok'  ).innerHTML = "-";
            document.getElementById('fld_senterr' ).innerHTML = "-";
            document.getElementById('fld_witsok'  ).innerHTML = "-";
            document.getElementById('fld_witserr' ).innerHTML = "-";
            document.getElementById('fld_dptdelay').innerHTML = "-";
            document.getElementById('fld_swapch12').innerHTML = "-";
            msg = "Ошибка: нет ответа";
            console.error("AJAX: " + msg + ": ", err);
            message(msg + "\n[" + err.message + "]", "error", 15000);
        })
}

function loadProtocol()
{
    fetch('?api_get_protocol')
        .then(response => {
            if (!response.ok) {
                throw new Error("Системная ошибка\n\n500 Internal Server Error\n\n" + response.status);
            }
            return response.json();
        })
        .then(data => {
            document.getElementById('log_file_lines').innerText = data.lines;
            document.getElementById('log_file_content').innerText = data.content;
        })
        .catch(err => {
            msg = "Ошибка: нет ответа";
            console.error("AJAX: " + msg + ": ", err);
            message(msg + "\n[" + err.message + "]", "error", 15000);
        })
}

function loadAndParseConfigToInputs()
{
    fetch('?api_get_config_files')
        .then(response => response.text())
        .then(data => {
            const lines = data.split('\n');

            /* Массив всех возможных полей для обнуления (включая SIU параметры) */
            const fields = ['host1','port11','port12','host2','port21','port22',
                            'host3','port31','port32','wits_port','proto_ver',
                            'ads_cmd_port','ads_data_port','ss_cmd_port',
                            'ss_dats_port','dtr_cmd_port',
                            'dtr_data_port','SystemUnits','Decimal'];
            fields.forEach(f => { document.getElementById('input_'+f).value = ''; });

            lines.forEach(line => {
                let clean = line.trim();
                if (clean.startsWith('#') || !clean.includes('=')) return;

                let kv = clean.split('=');
                let key = kv[0].trim();
                let val = kv[1].split('#')[0].trim(); 
                let input = document.getElementById('input_' + key);
                if (input) input.value = val;

            });
        })
        .catch(err => {
            msg = "Ошибка: нет ответа";
            console.error("AJAX: " + msg + ": ", err);
            message(msg + "\n[" + err.message + "]", "error", 15000);
        })
}

function saveConfig(event)
{
    event.preventDefault();

    const activeFormId = (currentMode === 'ATLAS') ? 'configFormAtlas' : 'configFormSIU';
    const form = document.getElementById(activeFormId);
    if (!form) return;

    const submitBtn = form.querySelector('button[type="submit"]');

    /* Блокируется кнопка и запускается спиннер */
    let originalBtnHtml = "";
    if (submitBtn) {
        const currentWidth = submitBtn.getBoundingClientRect().width;
        submitBtn.style.width = currentWidth + 'px';
        originalBtnHtml = submitBtn.innerHTML;
        submitBtn.disabled = true;
        submitBtn.innerHTML = '<span class="spinner"></span>Сохранение...';
        submitBtn.style.opacity = "0.74";
    }

    const formData = new URLSearchParams(new FormData(document.getElementById(activeFormId)));

    fetch('?api_save_config', {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: formData.toString()
    })
    .then(response => response.text())
    .then(result => {
      const status = result.trim();
      if (status === 'SUCCESS') {
          message("Конфигурация успешно сохранена", "info");
          toggleConfigMode('edit');
      } else if (status === 'ERR_500') {
          message("Системная ошибка\n\n500 Internal Server Error\n[" + status + "]", "error");
      } else {
          message("Не удалось сохранить конфигурацию\n[" + status + "]", "error");
      }
    })
    .catch(err => {
        msg = "Ошибка: нет ответа";
        console.error("AJAX: " + msg + ": ", err);
        message(msg + "\n[" + err.message + "]", "error", 15000);
    })
    .finally(() => {
      if (submitBtn) {
        submitBtn.disabled = false;
        submitBtn.innerHTML = originalBtnHtml ? originalBtnHtml : "Сохранить изменения";
        submitBtn.style.opacity = "1";
        submitBtn.style.width = '';
      }
    });
}

function loadADCConfig()
{
    fetch('?api_get_adc_config')
        .then(response => {
            if (!response.ok) {
                throw new Error("Системная ошибка\n\n500 Internal Server Error\n\n" + response.status);
            }
            return response.json();
        })
        .then(data => {
            document.getElementById('input_ref').value = data.ref || '—';
            document.getElementById('adc_scale').innerText = data.scale || '—';
        })
        .catch(err => {
            msg = "Ошибка: нет ответа";
            console.error("AJAX: " + msg + ": ", err);
            message(msg + "\n[" + err.message + "]", "error", 15000);
        })
}

function saveADCConfig(event)
{
    event.preventDefault();

    const form = document.getElementById('configADC');
    if (!form) return;

    const submitBtn = form.querySelector('button[type="submit"]');

    /* Блокируется кнопка и запускается спиннер */
    let originalBtnHtml = "";
    if (submitBtn) {
        const currentWidth = submitBtn.getBoundingClientRect().width;
        submitBtn.style.width = currentWidth + 'px';
        originalBtnHtml = submitBtn.innerHTML;
        submitBtn.disabled = true;
        submitBtn.innerHTML = '<span class="spinner"></span>Сохранение...';
        submitBtn.style.opacity = "0.74";
    }

    const formData = new URLSearchParams(new FormData(form));

    fetch('?api_save_adc_config', {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: formData.toString()
    })
    .then(response => response.text())
    .then(result => {
      const status = result.trim();
      if (status === 'SUCCESS') {
          message("Конфигурация успешно сохранена", "info");
          loadADCConfig();
      } else if (status === 'ERR_500') {
          message("Системная ошибка\n\n500 Internal Server Error\n[" + status + "]", "error");
      } else {
          message("Не удалось сохранить конфигурацию\n[" + status + "]", "error");
      }
    })
    .catch(err => {
        msg = "Ошибка: нет ответа";
        console.error("AJAX: " + msg + ": ", err);
        message(msg + "\n[" + err.message + "]", "error", 15000);
    })
    .finally(() => {
      if (submitBtn) {
        submitBtn.disabled = false;
        submitBtn.innerHTML = originalBtnHtml ? originalBtnHtml : "Сохранить изменения";
        submitBtn.style.opacity = "1";
        submitBtn.style.width = '';
      }
    });
}

function loadWitsConfig()
{
    fetch('?api_get_wits_config')
        .then(response => response.text())
        .then(data => {
            const lines = data.split('\n');

            /* Массив всех возможных полей для обнуления */
            const fields = ['wits_wellid', 'wits_recid', 'ps1_code', 'ps2_code',
                            'hkld_code', 'enc1_code',  'enc2_code'];
            fields.forEach(f => { document.getElementById('input_'+f).value = ''; });

            lines.forEach(line => {
                let clean = line.trim();
                if (clean.startsWith('#') || !clean.includes('=')) return;

                let kv = clean.split('=');
                let key = kv[0].trim();
                let val = kv[1].split('#')[0].trim(); 
                switch (key) {
                    case 'rec01':     key='wits_wellid'; break;
                    case 'rec03':     key='wits_recid';  break;
                    case 'pressure1': key='ps1_code';    break;
                    case 'pressure2': key='ps2_code';    break;
                    case 'hookload':  key='hkld_code';   break;
                    case 'encoder1':  key='enc1_code';   break;
                    case 'encoder2':  key='enc2_code';   break;
                    default:
                        console.warn("Unknown key: ", key);
                        key='a5ebaca';
                        break;
                }
                let input = document.getElementById('input_' + key);
                if (input) input.value = val;
            });
        })
        .catch(err => {
            msg = "Ошибка: нет ответа";
            console.error("AJAX: " + msg + ": ", err);
            message(msg + "\n[" + err.message + "]", "error", 15000);
        })
}


function saveWitsConfig(event)
{
    event.preventDefault();

    const form = document.getElementById('configWits');
    if (!form) return;

    const submitBtn = form.querySelector('button[type="submit"]');

    /* Блокируется кнопка и запускается спиннер */
    let originalBtnHtml = "";
    if (submitBtn) {
        const currentWidth = submitBtn.getBoundingClientRect().width;
        submitBtn.style.width = currentWidth + 'px';
        originalBtnHtml = submitBtn.innerHTML;
        submitBtn.disabled = true;
        submitBtn.innerHTML = '<span class="spinner"></span>Сохранение...';
        submitBtn.style.opacity = "0.74";
    }

    const formData = new URLSearchParams(new FormData(form));

    fetch('?api_save_wits_config', {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: formData.toString()
    })
    .then(response => response.text())
    .then(result => {
      const status = result.trim();
      if (status === 'SUCCESS') {
          message("Конфигурация успешно сохранена", "info");
          loadWitsConfig();
      } else if (status === 'ERR_500') {
          message("Системная ошибка\n\n500 Internal Server Error\n[" + status + "]", "error");
      } else {
          message("Не удалось сохранить конфигурацию\n[" + status + "]", "error");
      }
    })
    .catch(err => {
        msg = "Ошибка: нет ответа";
        console.error("AJAX: " + msg + ": ", err);
        message(msg + "\n[" + err.message + "]", "error", 15000);
    })
    .finally(() => {
      if (submitBtn) {
        submitBtn.disabled = false;
        submitBtn.innerHTML = originalBtnHtml ? originalBtnHtml : "Сохранить изменения";
        submitBtn.style.opacity = "1";
        submitBtn.style.width = '';
      }
    });
}


// Переключение режимов Просмотр / Редактирование
async function toggleSetupMode(mode)
{
    if (mode === 'edit') {
        document.getElementById('setup_view_mode').style.display = 'none';
        document.getElementById('setup_edit_mode').style.display = 'block';
        document.getElementById('btn_setup_edit').style.display = 'none';
        document.getElementById('btn_setup_cancel').style.display = 'inline-block';

        document.getElementById('input_setup_ip').value = document.getElementById('lbl_setup_ip').innerText;
        document.getElementById('input_setup_gw').value = document.getElementById('lbl_setup_gw').innerText === '—' ? '' : document.getElementById('lbl_setup_gw').innerText;
        document.getElementById('input_setup_mac').value = document.getElementById('lbl_setup_mac').innerText;
        document.getElementById('input_setup_ssh').value = document.getElementById('lbl_setup_ssh').innerText;
        document.getElementById('input_setup_ftp').value = document.getElementById('lbl_setup_ftp').innerText;
        document.getElementById('input_setup_http').value = document.getElementById('lbl_setup_http').innerText;
        document.getElementById('input_setup_lang').value = document.getElementById('lbl_setup_lang').innerText;
        document.getElementById('input_setup_sno').value = document.getElementById('lbl_setup_sno').innerText;
    } else {
        document.getElementById('setup_edit_mode').style.display = 'none';
        document.getElementById('setup_view_mode').style.display = 'block';
        document.getElementById('btn_setup_cancel').style.display = 'none';
        document.getElementById('btn_setup_edit').style.display = 'inline-block';
        loadSystemSetup();
    }
}


// Отправка измененных данных на сервер
function saveSystemSetup(event)
{
    event.preventDefault(); /* Мгновенно предотвращает стандартную отправку */

    const form = document.getElementById('sysSetupForm');
    const submitBtn = form.querySelector('button[type="submit"]');
    const cancelBtn = document.getElementById('btn_setup_cancel');

    if (submitBtn) {
        const currentWidth = submitBtn.getBoundingClientRect().width;
        submitBtn.style.width = currentWidth + 'px';
        submitBtn.disabled = true;
        submitBtn.innerHTML = '<span class="spinner"></span>Сохранение...';
        submitBtn.style.opacity = "0.74";
    }
    if (cancelBtn) cancelBtn.disabled = true;

    const formData = new URLSearchParams(new FormData(form));

    fetch('?api_save_setup', {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: formData.toString()
    })
    .then(response => response.text())
    .then(result => {
        const status = result.trim();
        if (status === 'SUCCESS') {
            message("Системные настройки обновлены", "info");
            toggleSetupMode('view');
        } else if (status === 'ERR_500') {
            message("Системная ошибка\n\n500 Internal Server Error\n[" + status + "]", "error");
        } else {
            message("Ошибка при сохранении системных настроек\n\n[" + status + "]", "error");
        }
    })
    .catch(err => {
        msg = "Ошибка: нет ответа";
        console.error("AJAX: " + msg + ": ", err);
        message(msg + "\n[" + err.message + "]", "error", 15000);
    })
    .finally(() => {
        if (submitBtn) {
            submitBtn.disabled = false;
            submitBtn.innerText = "Сохранить изменения";
            submitBtn.style.opacity = "1";
            submitBtn.style.width = '';
        }
        if (cancelBtn) cancelBtn.disabled = false;
    });
}

// Синхронизация времени
function syncTime(button)
{
    button.disabled = true;

    const now = new Date();
    const YYYY = now.getFullYear();
    const MM   = String(now.getMonth() + 1).padStart(2, '0');
    const DD   = String(now.getDate()).padStart(2, '0');
    const hh   = String(now.getHours()).padStart(2, '0');
    const mm   = String(now.getMinutes()).padStart(2, '0');
    const ss   = String(now.getSeconds()).padStart(2, '0');

    const hostTimeStr = `${YYYY}${MM}${DD}${hh}${mm}.${ss}`;

    fetch(`?set_time=${hostTimeStr}`)
      .then(response => response.text())
      .then(updatedTime => {
          if (updatedTime.includes("ERR")) {
              message("Ошибка установки времени на устройстве", "info");
          } else {
              document.getElementById('lbl_time').innerHTML = updatedTime.trim();
          }
      })
      .catch(err => {
          msg = "Ошибка: нет ответа";
          console.error("AJAX: " + msg + ": ", err);
          message(msg + "\n[" + err.message + "]", "error", 15000);
      })
      .finally(() => {
          button.disabled = false;
      });
}

// Функция обновления времени браузера
function updateBrowserClock()
{
    const now = new Date();
    const dayNameRaw   = new Intl.DateTimeFormat('ru-RU', { weekday: 'long' }).format(now);
    const monthNameRaw = new Intl.DateTimeFormat('ru-RU', { month: 'short' }).format(now);
    const dayNum       = new Intl.DateTimeFormat('ru-RU', { day: 'numeric' }).format(now);
    const year         = new Intl.DateTimeFormat('ru-RU', { year: 'numeric' }).format(now);

    const hours   = String(now.getHours()).padStart(2, '0');
    const minutes = String(now.getMinutes()).padStart(2, '0');
    const seconds = String(now.getSeconds()).padStart(2, '0');
    const timeStr = `${hours}:${minutes}:${seconds}`;

    const dayName   = (dayNameRaw.charAt(0).toUpperCase() + dayNameRaw.slice(1)).replace('.', '');
    const monthName = (monthNameRaw.charAt(0).toUpperCase() + monthNameRaw.slice(1)).replace('.', '');
    /* Формат: Mon Jul 27 13:19:34 2026 */
    document.getElementById('lbl_date').innerHTML = `${dayName}, ${dayNum} ${monthName} ${year} &nbsp; ${timeStr}`;
}

function fileSelectionCancel(input, text)
{
    console.log(input.id + " - выбор файла отменен", text);
    if (!input) return;

    const button = input.parentNode.querySelector('.btn-updates');
    if (button) {
        button.innerHTML = text.trim();
        button.disabled = false;
    }
}

async function update_procedure(mode) {
    btn = document.getElementById('btn_' + mode);
    btn.disable = true;
    file_select = document.getElementById('input_file_' + mode);

    const currentWidth = btn.offsetWidth;
    btn.style.minWidth = currentWidth + 'px';
    const originalText = btn.innerText;

    console.log(btn.innerText);
    try {
        btn.innerText = 'Проверка системы...';
        const statusResponse = await fetch('?api_app_status');
        const appStatus = await statusResponse.text();
        if (appStatus.trim() === "RUNNING") {
            message("Необходимо остановить систему перед обновлением прошивки", "error");
            return;
        }
        btn.innerText = 'Выбор файла...';
        if (file_select !== null) {
            file_select.click();
        }
    } catch (err) {
        btn.innerText = originalText;
        msg = "Ошибка в процедуре обновления";
        console.error(msg + ':', err);
        message(msg + "\n\n" + err, "error");
    } finally {
        btn.disable = false;
        btn.innerText = originalText;
    }
}

async function uploadFile(input)
{
    if (input.files.length === 0) return;
    const file = input.files[0];

    const btn = input.parentNode.querySelector('.btn-updates');
    if (!btn) return;

    btn.disabled = true;
    const originalText = btn.innerText;
    const action = btn.id.replace('btn_', '');

    btn1 = document.getElementById('btn_update_app');
    btn1.disabled = true;
    btn2 = document.getElementById('btn_update_wcp');
    btn2.disabled = true;
    btn3 = document.getElementById('btn_update_firmware');
    btn3.disabled = true;

    btn.innerText = 'Подтверждение...';
    if (!confirm(`Файл: ${file.name}\nРазмер: ${(file.size / 1024 / 1024).toFixed(2)} МБ\n\nПродолжать?`)) {
        input.value = '';
        btn.disabled = false;
        btn.innerText = originalText;
        btn1.disabled = false;
        btn2.disabled = false;
        btn3.disabled = false;
        return;
    }

    const reader = new FileReader();
    reader.onload = function(e) {
      try {
        btn.innerText = 'Расчет SHA-256...';
        const arrayBuffer = e.target.result;
        const calculatedHash = sha256(arrayBuffer);
        console.info('calculatedHash: ', calculatedHash);

        btn.innerText = 'Загрузка...';
        btn.classList.add('btn-uploading');

        const formData = new FormData();
        formData.append('firmware', file);

        const api_url = "?action=" + action.trim() + `&fn=${file.name}&expected_hash=${calculatedHash}`;
        fetch(api_url, {
            method: 'POST',
            body: formData
        })
        .then(response => {
            if (!response.ok) {
                throw new Error(`Ошибка: ${response.status}`);
            }
            return response.text();
        })
        .then(result => {
            const status = result.trim();
            console.log("Status", status);
            note="\n\nsee /var/log/" + action.trim() + ".log"
            if (status === "SUCCESS") {
                message("Обновлено успешно", "success", 30000);
            } else if (status === "ERR_APP_NOT_STOP") {
                message("Необходимо остановить систему", "info");

            /* POST data parsing error messages */
            } else if (status === "ERR_HASH_MISMATCH") {
                message("Ошибка контрольной суммы" + note, "error");
            } else if (status === "ERR_BAD_EXPECTED_HASH") {
                message("Не верный формат контрольной суммы" + note, "error");
            } else if (status === "ERR_EMPTY_CONTENT") {
                message("Передан пустой блок данных" + note, "error");
            } else if (status === "ERR_CONTENT_TOO_MUCH_SIZE") {
                message("Слишком большой размер обновления" + note, "error");
            } else if (status === "ERR_UPDATE_CONTENT_WRONG") {
                message("Неверное содержимое обновления" + note, "error");
            } else if (status === "ERR_PARSE_MULTIPART") {
                message("Передан некорректный блок данных" + note, "error");


            /* unpacking update messages */
            } else if (status === "ERR_FILE_NOT_SAVED") {
                message("Ошибка сохранения принятых данных" + note, "error");
            } else if (status === "ERR_ARCH_FORMAT_WRONG") {
                message("Неподдерживаемый тип сжатия" + note, "error");
            } else if (status === "ERR_ARCH_EXT_WRONG") {
                message("Неверное расширение файла" + note, "error");
            } else if (status === "ERR_UNPACK_FAILED") {
                message("Ошибка при распаковке обновления" + note, "error");
            } else if (status === "ERR_UPDATE_FAILED") {
                message("Ошибка в процедуре обновления" + note, "error");

            } else if (status === "ERR_BACKUP_FAILED") {
                message("Ошибка создания резервной копии текущей прошивки" + note, "error");

            /* firmware update messages */
            } else if (status === "ERR_MOUNT_FAILED") {
                message("Ошибка монтирования раздела загрузки" + note, "error");
            } else if (status === "ERR_UMOUNT_FAILED") {
                message("Ошибка демонтирования раздела загрузки" + note, "error");
            } else if (status === "SUCCESS_FIRMWARE") {
                message("Обновлено успешно\n\nТребуется перезапуск устройства", "success", 30000);

            } else if (status === "ERR_500") {
                message("Системная ошибка\n\n500 Internal Server Error\n[" + status + "]", "error");
            } else {
                message("Ошибка при обновлении\n" + status + note, "error", 30000);
            }
        })
        .catch(err => {
            msg = "Ошибка: нет ответа";
            console.error("AJAX: " + msg + ": ", err);
            if (err.name === 'TypeError' && err.message.includes('fetch')) {
                message(msg + "\n500 Internal Server Error (TypeError)", "error", 15000);
            } else {
                message(msg + "\n[" + err.message + "]", "error", 15000);
            }
        })
        .finally(() => {
            btn.disabled = false;
            btn.innerText = originalText;
            btn.classList.remove('btn-uploading');
            input.value = '';
            btn1.disabled = false;
            btn2.disabled = false;
            btn3.disabled = false;
        });

    } catch (err) {
        msg = "Ошибка при обработке";
        console.error(msg + ":", err);
        message(msg + "\n\n" + err.message, "error");
        btn.disabled = false;
        btn.innerText = originalText;
        input.value = '';
        btn1.disabled = false;
        btn2.disabled = false;
        btn3.disabled = false;
    }
  };

  reader.onerror = function() {
      msg = "Не удалось прочитать файл";
      console.error(msg);
      message(msg + "\n[" + err.message + "]", "error", 15000);
      btn.disabled = false;
      btn.innerText = originalText;
      input.value = '';
      btn1.disabled = false;
      btn2.disabled = false;
      btn3.disabled = false;
  };

  console.info("file: ", file.name, "\nsize: ", file.size);
  reader.readAsArrayBuffer(file);
}

function message(text, type = 'info', timeout = 5000, style = '')
{
    const container = document.getElementById('message-container');
    if (!container) return;

    container.innerHTML = '';

    const oldTimerId = container.getAttribute('data-message-timer');
    if (oldTimerId) {
        clearTimeout(parseInt(oldTimerId, 10));
    }

    const msg = document.createElement('div');
    msg.className = `custom-message ${type}`;

    let htmlText = text.replace(/\r?\n/g, '<br>');
    msg.innerHTML = `
        <span class="custom-message-text">${htmlText}</span>
        <span class="custom-message-close" onclick="this.parentElement.remove();">&times;</span>
    `;

    if (style !== '') {
       msg.style.cssText += "; " + style;
    }

    container.appendChild(msg);

    setTimeout(() => {
        if (msg.parentNode) msg.classList.add('show');
    }, 10);

    const newTimerId = setTimeout(() => {
        if (msg.parentNode) {
            msg.classList.remove('show');
            msg.addEventListener('transitionend', () => {
                msg.remove();
            });
        }
    }, timeout);

    container.setAttribute('data-message-timer', newTimerId);
}


//document.addEventListener("DOMContentLoaded", () => {
//    updateBrowserClock();
//    setInterval(updateBrowserClock, 1000);
//});

window.onload = function()
{
    document.getElementById('title').innerText = MODE_TITLE;
    document.getElementById('lbl_mode').innerText = MODE_TITLE;
    document.getElementById('title_wcp_ver').innerText = WCPVER_TITLE;
    //document.getElementById('status_content').innerText = STATUSFNAME;

    updateBrowserClock();
    setInterval(updateBrowserClock, 1000);
    switchView('status');
};
