(function () {
    'use strict';

    const SPELLS = window.SPELLS || [];
    const ITEMS  = window.ITEMS  || [];
    const spellsById = new Map(SPELLS.map(s => [s.id, s]));
    const itemsById  = new Map(ITEMS.map(i => [i.id, i]));

    const ALL_LEVELS  = [0,1,2,3,4,5,6,7,8,9];
    const ALL_SCHOOLS = Array.from(new Set(
        SPELLS.map(s => s.school)
              .filter(s => s && !/^дюнамантия/i.test(s))
    )).sort();
    const ALL_CLASSES = Array.from(new Set(
        SPELLS.flatMap(s => toArray(s.classes))
    )).sort();

    const ALL_ITEM_TYPES = Array.from(new Set(
        ITEMS.map(i => i.type).filter(Boolean)
    )).sort((a, b) => a.localeCompare(b, 'ru'));

    const ITEM_RARITY_ORDER = [
        'common','uncommon','rare','very_rare','legendary','artifact','varies','none'
    ];
    const ITEM_RARITY_LABELS = {
        common:    'Обычный',
        uncommon:  'Необычный',
        rare:      'Редкий',
        very_rare: 'Очень редкий',
        legendary: 'Легендарный',
        artifact:  'Артефакт',
        varies:    'Варьируется',
        none:      'Без редкости'
    };

    function toArray(v) {
        if (v == null) return [];
        return Array.isArray(v) ? v : [v];
    }

    function componentsShort(c) {
        if (!c) return '';
        return (c.verbal ? 'В' : '.') + (c.somatic ? 'С' : '.') + (c.material ? 'М' : '.');
    }

    function levelLabel(lvl) {
        if (lvl === 0) return 'Заговор';
        if (lvl == null) return '—';
        return lvl + ' круг';
    }

    function itemRarityKey(it) {
        const k = (it.rarity_key || 'none').toLowerCase();
        return ITEM_RARITY_LABELS[k] ? k : 'none';
    }

    // ===== State =====
    const state = {
        search: '',
        // spells
        levels:  new Set(),
        schools: new Set(),
        classes: new Set(),
        ritual:  false,
        concentration: false,
        // items
        itemTypes:     new Set(),
        itemRarities:  new Set(),
        itemAttunement: null   // null | true | false
    };

    // ===== Router =====
    function parseRoute() {
        const hash = window.location.hash.slice(1) || '/';
        if (hash.startsWith('/spell/')) {
            return { view: 'spell', id: decodeURIComponent(hash.slice('/spell/'.length)) };
        }
        if (hash.startsWith('/item/')) {
            return { view: 'item', id: decodeURIComponent(hash.slice('/item/'.length)) };
        }
        if (hash === '/tracker') return { view: 'tracker' };
	if (hash === '/attunement') return { view: 'attunement' };
        if (hash === '/items')   return { view: 'items' };
        if (hash === '/spells')  return { view: 'spells' };
        // legacy / root -> redirect to /spells
        return { view: 'redirect', to: '/spells' };
    }
    function navigate(path) { window.location.hash = path; }

    // ===== DOM helper =====
    function el(tag, attrs, children) {
        const e = document.createElement(tag);
        if (attrs) {
            for (const k in attrs) {
                const v = attrs[k];
                if (v == null || v === false) continue;
                if (k === 'className') e.className = v;
                else if (k === 'innerHTML') e.innerHTML = v;
                else if (k.startsWith('on') && typeof v === 'function') {
                    e.addEventListener(k.slice(2).toLowerCase(), v);
                } else if (v === true) e.setAttribute(k, '');
                else e.setAttribute(k, v);
            }
        }
        if (children != null) {
            (Array.isArray(children) ? children : [children]).forEach(c => {
                if (c == null) return;
                e.appendChild(typeof c === 'string' ? document.createTextNode(c) : c);
            });
        }
        return e;
    }

    function onFilterChange() {
    const r = parseRoute();
    if (r.view === 'spells') {
        renderFilters('spells');
        renderSpellsList();
    } else if (r.view === 'items') {
        renderFilters('items');
        renderItemsList();
    } else if (r.view === 'spell') {
        navigate('/spells');
    } else if (r.view === 'item') {
        navigate('/items');
    } else {
        navigate('/spells');
    }
}

    function updateNav(view) {
        let target = null;
        if (view === 'spells' || view === 'spell')       target = 'spells';
        else if (view === 'items' || view === 'item')    target = 'items';
        else if (view === 'tracker')                     target = 'tracker';
	else if (view === 'attunement')                  target = 'attunement';
        document.querySelectorAll('header nav a').forEach(a => {
            a.classList.toggle('active', a.getAttribute('data-route') === target);
        });
    }

    // ===== Filters =====
    function multiSection(title, values, set, extraClass, formatLabel) {
        const sec = el('div', {
            className: 'filter-group' + (extraClass ? ' ' + extraClass : '')
        }, el('h3', null, title));
        const grp = el('div', { className: 'btn-group' });
        values.forEach(v => {
            const active = set.has(v);
            grp.appendChild(el('button', {
                className: 'filter-btn' + (active ? ' active' : ''),
                onClick: () => {
                    if (set.has(v)) set.delete(v); else set.add(v);
                    onFilterChange();
                }
            }, formatLabel ? formatLabel(v) : String(v)));
        });
        sec.appendChild(grp);
        return sec;
    }

    function raritySection() {
        const sec = el('div', { className: 'filter-group column' }, el('h3', null, 'Редкость'));
        const grp = el('div', { className: 'btn-group' });
        ITEM_RARITY_ORDER.forEach(rk => {
            const active = state.itemRarities.has(rk);
            grp.appendChild(el('button', {
                className: 'filter-btn rarity-btn rarity-' + rk + (active ? ' active' : ''),
                onClick: () => {
                    if (state.itemRarities.has(rk)) state.itemRarities.delete(rk);
                    else state.itemRarities.add(rk);
                    onFilterChange();
                }
            }, ITEM_RARITY_LABELS[rk]));
        });
        sec.appendChild(grp);
        return sec;
    }

    function attunementSection() {
        const sec = el('div', { className: 'filter-group' }, el('h3', null, 'Настройка'));
        const grp = el('div', { className: 'btn-group attunement-group' });

        function toggleBtn(value, label) {
            const active = state.itemAttunement === value;
            grp.appendChild(el('button', {
                className: 'filter-btn' + (active ? ' active' : ''),
                onClick: () => {
                    state.itemAttunement = active ? null : value;
                    onFilterChange();
                }
            }, label));
        }
        toggleBtn(true,  'Требуется');
        toggleBtn(false, 'Не требуется');

        sec.appendChild(grp);
        return sec;
    }

    function spellsOtherSection() {
        const sec = el('div', { className: 'filter-group other' },
                       el('h3', null, 'Прочее'));
        const grp = el('div', { className: 'btn-group' });
        function toggle(title, key) {
            const active = state[key];
            grp.appendChild(el('button', {
                className: 'filter-btn' + (active ? ' active' : ''),
                onClick: () => {
                    state[key] = !state[key];
                    onFilterChange();
                }
            }, title));
        }
        toggle('Ритуал', 'ritual');
        toggle('Концентрация', 'concentration');
        sec.appendChild(grp);
        return sec;
    }

    function resetButton(section) {
        return el('button', {
            className: 'filter-reset',
            onClick: () => {
                state.search = '';
                document.getElementById('search').value = '';
                if (section === 'spells') {
                    state.levels  = new Set();
                    state.schools = new Set();
                    state.classes = new Set();
                    state.ritual  = false;
                    state.concentration = false;
                } else if (section === 'items') {
                    state.itemTypes      = new Set();
                    state.itemRarities   = new Set();
                    state.itemAttunement = null;
                }
                onFilterChange();
            }
        }, 'Сбросить фильтры');
    }

    function renderFilters(section) {
        const root = document.getElementById('filters');
        root.innerHTML = '';

        if (section === 'items') {
            root.appendChild(multiSection('Тип', ALL_ITEM_TYPES, state.itemTypes, 'column'));
            root.appendChild(raritySection());
            root.appendChild(attunementSection());
            root.appendChild(resetButton('items'));
            return;
        }

        // spells (default)
        root.appendChild(multiSection('Уровень', ALL_LEVELS,  state.levels,  'levels'));
        root.appendChild(multiSection('Школа',   ALL_SCHOOLS, state.schools, 'column'));
        root.appendChild(multiSection('Класс',   ALL_CLASSES, state.classes, 'column'));
        root.appendChild(spellsOtherSection());
        root.appendChild(resetButton('spells'));
    }

    function filterSpells() {
        const q = state.search.toLowerCase();
        return SPELLS.filter(s => {
            if (q) {
                const ru = (s.name && s.name.ru || '').toLowerCase();
                const en = (s.name && s.name.en || '').toLowerCase();
                if (!ru.includes(q) && !en.includes(q)) return false;
            }
            if (state.levels.size  && !state.levels.has(s.level))   return false;
            if (state.schools.size && !(s.school && state.schools.has(s.school))) return false;
            if (state.classes.size) {
                const cls = toArray(s.classes);
                if (!cls.some(c => state.classes.has(c))) return false;
            }
            if (state.ritual && !s.ritual) return false;
            if (state.concentration && !s.concentration) return false;
            return true;
        });
    }

    function filterItems() {
        const q = state.search.toLowerCase();
        return ITEMS.filter(it => {
            if (q) {
                const ru    = (it.name && it.name.ru || '').toLowerCase();
                const en    = (it.name && it.name.en || '').toLowerCase();
                const proto = (it.prototype || '').toLowerCase();
                if (!ru.includes(q) && !en.includes(q) && !proto.includes(q)) return false;
            }
            if (state.itemTypes.size && !state.itemTypes.has(it.type)) return false;
            if (state.itemRarities.size && !state.itemRarities.has(itemRarityKey(it))) return false;
            if (state.itemAttunement === true  && !it.attunement) return false;
            if (state.itemAttunement === false &&  it.attunement) return false;
            return true;
        });
    }

    // ===== Spell list =====
    function renderSpellsList() {
        const root = document.getElementById('content');
        root.innerHTML = '';

        const spells = filterSpells();
        root.appendChild(el('div', { className: 'list-header' },
            `${spells.length} из ${SPELLS.length}`));

        if (!spells.length) {
            root.appendChild(el('p', { className: 'empty' }, 'Ничего не найдено'));
            return;
        }

        const ul = el('ul', { className: 'spell-list' });
        spells.forEach(s => {
            const badges = [];
            if (s.ritual)        badges.push('Р');
            if (s.concentration) badges.push('К');
            const schoolText = (s.school || '')
                + (badges.length ? ' [' + badges.join('') + ']' : '');

            const a = el('a', {
                className: 'spell-link',
                href: '#/spell/' + encodeURIComponent(s.id)
            }, [
                el('span', { className: 'spell-level' }, `[${s.level}]`),
                el('span', { className: 'spell-name' },  (s.name && s.name.ru) || '—'),
                el('span', { className: 'spell-school' }, schoolText),
                el('span', { className: 'spell-components' }, componentsShort(s.components))
            ]);
            ul.appendChild(el('li', { className: 'spell-item' }, a));
        });
        root.appendChild(ul);
    }

    // ===== Spell detail =====
    function renderSpell(id) {
        const root = document.getElementById('content');
        root.innerHTML = '';
        const s = spellsById.get(id);
        if (!s) {
            root.appendChild(el('p', { className: 'empty' },
                `Заклинание не найдено: ${id}`));
            return;
        }

        const box = el('div', { className: 'spell-detail' });
        box.appendChild(el('a', {
            className: 'back-link',
            href: '#/spells',
            onClick: (e) => { e.preventDefault(); navigate('/spells'); }
        }, '← К списку заклинаний'));

        const titleText = (s.name && s.name.ru) || '—';
        let titleNode;
        if (s.url) {
            titleNode = el('a', {
                href: s.url,
                target: '_blank',
                rel: 'noopener noreferrer',
                title: 'Открыть на dnd.su'
            }, [titleText, el('span', { className: 'external-icon' }, '↗')]);
        } else {
            titleNode = document.createTextNode(titleText);
        }
        box.appendChild(el('h2', { className: 'spell-title' }, titleNode));

        if (s.name && s.name.en) {
            box.appendChild(el('div', { className: 'spell-subtitle' },
                `[${s.name.en}]`));
        }

        const metaBits = [`${levelLabel(s.level)}, ${s.school || '—'}`];
        if (s.ritual)        metaBits.push('ритуал');
        if (s.concentration) metaBits.push('концентрация');
        if (s.dunamancy) {
            metaBits.push('дюнамантия' +
                (s.dunamancy_sub ? ': ' + s.dunamancy_sub : ''));
        }
        box.appendChild(el('div', { className: 'spell-meta' }, metaBits.join(' · ')));

        box.appendChild(renderSpellTrackerButton(s));

        const params = el('ul', { className: 'spell-params' });
        const add = (label, value) => {
            if (value) params.appendChild(el('li', null, [
                el('strong', null, label + ': '), String(value)
            ]));
        };
        add('Время накладывания', s.cast_time);
        add('Дистанция',          s.range);
        add('Длительность',       s.duration);
        add('Компоненты',         s.components && s.components.raw);
        add('Классы',             toArray(s.classes).join(', '));
        add('Подклассы',          toArray(s.subclasses).join(', '));
        box.appendChild(params);

        box.appendChild(el('div', {
            className: 'spell-description',
            innerHTML: (s.description && s.description.html) || ''
        }));

        root.appendChild(box);
    }

    // ===== Item list =====
    function renderItemsList() {
    const root = document.getElementById('content');
    root.innerHTML = '';

    const items = filterItems().sort((a, b) =>
        ((a.name && a.name.ru) || '').localeCompare(
         (b.name && b.name.ru) || '', 'ru'));

    root.appendChild(el('div', { className: 'list-header' },
        `${items.length} из ${ITEMS.length}`));

    if (!items.length) {
        root.appendChild(el('p', { className: 'empty' }, 'Ничего не найдено'));
        return;
    }

    const ul = el('ul', { className: 'item-list' });
    items.forEach(it => {
        const rk = itemRarityKey(it);
        const rarityText = it.rarity || ITEM_RARITY_LABELS[rk] || '';
        const att = it.attunement ? 'Н' : '';

        const a = el('a', {
            className: 'item-link',
            href: '#/item/' + encodeURIComponent(it.id)
        }, [
            el('span', { className: 'item-type' }, it.type || '—'),
            el('span', { className: 'item-name' }, (it.name && it.name.ru) || '—'),
            el('span', { className: 'item-rarity rarity-' + rk }, rarityText),
            el('span', { className: 'item-attunement' }, att)
        ]);

        const li = el('li', { className: 'item-item' });
        li.appendChild(a);

        if (it.attunement) {
            const existingSlot = itemAttunementSlot(it.id);
            const freeSlot = firstEmptyAttunementSlot();

            let btnText, btnTitle, disabled, extraClass = '';
            if (existingSlot >= 0) {
                btnText = '✓';
                btnTitle = `Уже в слоте настроек ${existingSlot + 1}`;
                disabled = true;
                extraClass = ' added';
            } else if (freeSlot < 0) {
                btnText = '–';
                btnTitle = 'Все слоты настроек заняты';
                disabled = true;
            } else {
                btnText = '+';
                btnTitle = 'Добавить в настройки';
                disabled = false;
            }

            const btn = el('button', {
                className: 'item-attune-btn' + extraClass,
                title: btnTitle,
                disabled: disabled ? 'disabled' : null,
                onClick: (e) => {
                    e.preventDefault();
                    e.stopPropagation();
                    if (disabled) return;
                    if (addItemToAttunement(it.id)) {
                        renderItemsList();
                    }
                }
            }, btnText);
            li.appendChild(btn);
        }

        ul.appendChild(li);
    });
    root.appendChild(ul);
}

function renderItemAttunementButton(it) {
    if (!it.attunement) return null;

    const wrap = el('div', { className: 'detail-tracker' });
    const existingSlot = itemAttunementSlot(it.id);

    if (existingSlot >= 0) {
        wrap.appendChild(el('div', { className: 'detail-tracker-info' }, [
            'В настройках: ',
            el('strong', null, `слот ${existingSlot + 1}`),
            el('button', {
                className: 'detail-tracker-remove',
                onClick: () => {
                    const name = (it.name && it.name.ru) || it.id;
                    if (!confirm(`Убрать «${name}» из настроек?`)) return;
                    attunement.slots[existingSlot] = null;
                    saveAttunement();
                    renderItem(it.id);
                }
            }, 'Убрать')
        ]));
        return wrap;
    }

    const freeSlot = firstEmptyAttunementSlot();
    if (freeSlot < 0) {
        wrap.appendChild(el('div', { className: 'detail-tracker-info muted' },
            'Все слоты настроек заняты. Освободите слот или включите ' +
            'Таинственное Слияние / Изобретателя в разделе «Настройки».'));
        return wrap;
    }

    wrap.appendChild(el('button', {
        className: 'btn-add-to-tracker',
        onClick: () => {
            if (addItemToAttunement(it.id)) {
                renderItem(it.id);
            }
        }
    }, '+ Добавить в настройки'));
    return wrap;
}

    // ===== Item detail =====
    function renderItem(id) {
        const root = document.getElementById('content');
        root.innerHTML = '';
        const it = itemsById.get(id);
        if (!it) {
            root.appendChild(el('p', { className: 'empty' },
                `Предмет не найден: ${id}`));
            return;
        }

        const rk = itemRarityKey(it);
        const box = el('div', { className: 'item-detail' });
        box.appendChild(el('a', {
            className: 'back-link',
            href: '#/items',
            onClick: (e) => { e.preventDefault(); navigate('/items'); }
        }, '← К списку предметов'));

        const titleText = (it.name && it.name.ru) || '—';
        let titleNode;
        if (it.url) {
            titleNode = el('a', {
                href: it.url,
                target: '_blank',
                rel: 'noopener noreferrer',
                title: 'Открыть на dnd.su'
            }, [titleText, el('span', { className: 'external-icon' }, '↗')]);
        } else {
            titleNode = document.createTextNode(titleText);
        }
        box.appendChild(el('h2', { className: 'item-title' }, titleNode));

        if (it.name && it.name.en) {
            box.appendChild(el('div', { className: 'item-subtitle' },
                `[${it.name.en}]`));
        }

        const metaBits = [];
        let typeText = it.type || '—';
        if (it.prototype) typeText += ` (${it.prototype})`;
        metaBits.push(typeText);

        if (it.rarity) {
            metaBits.push(it.rarity);
        } else if (rk === 'none') {
            metaBits.push('без редкости');
        } else if (rk === 'varies') {
            metaBits.push('редкость варьируется');
        }

        if (it.attunement) {
            let attText = 'требуется настройка';
            if (it.attunement_note) attText += ` (${it.attunement_note})`;
            metaBits.push(attText);
        }

        box.appendChild(el('div', { className: 'item-meta' }, metaBits.join(' · ')));

const attBtn = renderItemAttunementButton(it);
if (attBtn) box.appendChild(attBtn);

const params = el('ul', { className: 'item-params' });
        const add = (label, value) => {
            if (value) params.appendChild(el('li', null, [
                el('strong', null, label + ': '), String(value)
            ]));
        };

        if (Array.isArray(it.rarity_variants) && it.rarity_variants.length) {
            const variants = it.rarity_variants
    .map(v => v.bonus ? `${v.bonus} — ${v.rarity}` : v.rarity)
    .join(', ');
            add('Варианты редкости', variants);
        }

        if (it.price_text)    add('Рекомендованная стоимость', it.price_text);
        if (it.attunement_note && !it.attunement) add('Настройка', it.attunement_note);

        if (params.children.length) box.appendChild(params);

        box.appendChild(el('div', {
            className: 'item-description',
            innerHTML: (it.description && it.description.html) || ''
        }));

        if (it.additional_info && it.additional_info.html) {
            const addBox = el('div', { className: 'item-additional-info' }, [
                el('h3', null, 'Дополнительно'),
                el('div', { innerHTML: it.additional_info.html })
            ]);
            box.appendChild(addBox);
        }

        root.appendChild(box);
    }

    // ===== Main render =====
    function render() {
        const r = parseRoute();
        if (r.view === 'redirect') { navigate(r.to); return; }

        document.body.classList.toggle('view-tracker', r.view === 'tracker');
	document.body.classList.toggle('view-attunement', r.view === 'attunement');
        document.body.classList.toggle('view-items',   r.view === 'items' || r.view === 'item');
        document.body.classList.toggle('view-spells',  r.view === 'spells' || r.view === 'spell');

        updateNav(r.view);

        const section =
            (r.view === 'spells' || r.view === 'spell') ? 'spells' :
            (r.view === 'items'  || r.view === 'item')  ? 'items'  : null;

        if (section) renderFilters(section);

        if (r.view === 'spell')        renderSpell(r.id);
        else if (r.view === 'item')    renderItem(r.id);
        else if (r.view === 'tracker') renderTracker();
	else if (r.view === 'attunement') renderAttunement();
        else if (r.view === 'items')   renderItemsList();
        else                           renderSpellsList();
    }

    // ===== Spell detail: tracker integration =====
    let detailModalSpell = null;

    function findSpellLocation(spellId) {
        for (const b of tracker.buckets) {
            if (b.cantrips.includes(spellId)) return { bucketName: b.name, isCantrip: true };
            if (b.spells.includes(spellId))   return { bucketName: b.name, isCantrip: false };
        }
        if (tracker.other.cantrips.includes(spellId))
            return { bucketName: tracker.other.name, isCantrip: true, isOther: true };
        if (tracker.other.spells.includes(spellId))
            return { bucketName: tracker.other.name, isCantrip: false, isOther: true };
        return null;
    }

    function removeSpellFromTracker(spellId) {
        for (const b of tracker.buckets) {
            let idx = b.cantrips.indexOf(spellId);
            if (idx >= 0) { b.cantrips.splice(idx, 1); saveTracker(); return; }
            idx = b.spells.indexOf(spellId);
            if (idx >= 0) { b.spells.splice(idx, 1); saveTracker(); return; }
        }
        let idx = tracker.other.cantrips.indexOf(spellId);
        if (idx >= 0) { tracker.other.cantrips.splice(idx, 1); saveTracker(); return; }
        idx = tracker.other.spells.indexOf(spellId);
        if (idx >= 0) { tracker.other.spells.splice(idx, 1); saveTracker(); return; }
    }

    function renderSpellTrackerButton(spell) {
        const wrap = el('div', { className: 'detail-tracker' });
        const status = spellStatus(spell.id);

        if (status === null) {
            wrap.appendChild(el('button', {
                className: 'btn-add-to-tracker',
                onClick: () => openDetailAddModal(spell)
            }, '+ Добавить в колоду'));
            return wrap;
        }

        const loc = findSpellLocation(spell.id);
        if (status === 'hidden') {
            wrap.appendChild(el('div', { className: 'detail-tracker-info muted' }, [
                'Заклинание в скрытом «Прочее». Включите его в ',
                el('a', { href: '#/tracker', onClick: (e) => { e.preventDefault(); navigate('/tracker'); } }, 'колоде'),
                ', чтобы увидеть или убрать.'
            ]));
            return wrap;
        }

        const sectionLabel = loc.isCantrip ? 'заговоры' : 'заклинания';
        wrap.appendChild(el('div', { className: 'detail-tracker-info' }, [
            'В колоде: ',
            el('strong', null, `${loc.bucketName} (${sectionLabel})`),
            el('button', {
                className: 'detail-tracker-remove',
                onClick: () => {
                    const name = (spell.name && spell.name.ru) || spell.id;
                    if (!confirm(`Убрать «${name}» из колоды?`)) return;
                    removeSpellFromTracker(spell.id);
                    renderSpell(spell.id);
                }
            }, 'Убрать')
        ]));
        return wrap;
    }

    function openDetailAddModal(spell) {
        detailModalSpell = spell;
        renderDetailAddModal();
    }

    function closeDetailAddModal() {
        detailModalSpell = null;
        const m = document.getElementById('modal');
        if (m) m.remove();
        document.removeEventListener('keydown', onDetailModalKey);
    }

    function onDetailModalKey(e) { if (e.key === 'Escape') closeDetailAddModal(); }

    function renderDetailAddModal() {
        const old = document.getElementById('modal');
        if (old) old.remove();
        const spell = detailModalSpell;
        if (!spell) return;

        const isCantrip = spell.level === 0;

        const overlay = el('div', { id: 'modal', className: 'modal-overlay' });
        let downOnOverlay = false;
        overlay.addEventListener('mousedown', (e) => { downOnOverlay = (e.target === overlay); });
        overlay.addEventListener('mouseup', (e) => {
            if (downOnOverlay && e.target === overlay) closeDetailAddModal();
            downOnOverlay = false;
        });

        const box = el('div', { className: 'modal-box' });
        box.appendChild(el('div', { className: 'modal-head' }, [
            el('h3', null, `Добавить «${(spell.name && spell.name.ru) || spell.id}»`),
            el('button', { className: 'modal-close', onClick: closeDetailAddModal }, '×')
        ]));

        box.appendChild(el('div', { className: 'modal-hint' },
            isCantrip
                ? 'Это заговор — можно добавить только в слоты заговоров.'
                : 'Это заклинание — можно добавить только в слоты заклинаний.'));

        const listBox = el('div', { className: 'modal-list' });
        renderDetailAddBuckets(listBox, spell);
        box.appendChild(listBox);

        overlay.appendChild(box);
        document.body.appendChild(overlay);
        document.addEventListener('keydown', onDetailModalKey);
    }

    function renderDetailAddBuckets(listBox, spell) {
        listBox.innerHTML = '';

        const isCantrip = spell.level === 0;
        const currentStatus = spellStatus(spell.id);

        const all = tracker.buckets.map(b => ({ bucket: b, name: b.name, isOther: false }));
        if (tracker.otherVisible) {
            all.push({ bucket: tracker.other, name: tracker.other.name, isOther: true });
        }

        if (all.length === 0) {
            listBox.appendChild(el('div', { className: 'empty' }, 'Нет активных корзин.'));
            listBox.appendChild(el('button', {
                className: 'btn-add-to-tracker',
                onClick: () => { closeDetailAddModal(); navigate('/tracker'); }
            }, 'Перейти в колоду'));
            return;
        }

        const ul = el('ul', { className: 'modal-bucket-list' });

        for (const { bucket, name, isOther } of all) {
            const list  = isCantrip ? bucket.cantrips : bucket.spells;
            const limit = isCantrip ? bucket.cantripLimit : bucket.spellLimit;
            const count = list.length;

            const inThisBucket   = list.includes(spell.id);
            const inAnotherBucket = currentStatus === 'visible' && !inThisBucket;
            const full           = count >= limit;

            let btnText, btnTitle, disabled, rowState;
            if (inThisBucket) {
                btnText = '✓'; btnTitle = 'Уже добавлено сюда'; disabled = true;  rowState = 'added';
            } else if (inAnotherBucket) {
                btnText = '✓'; btnTitle = 'Уже в другой корзине'; disabled = true;  rowState = 'added';
            } else if (full) {
                btnText = '–'; btnTitle = 'Все слоты заняты';     disabled = true;  rowState = 'full';
            } else {
                btnText = '+'; btnTitle = 'Добавить';             disabled = false; rowState = '';
            }

            const countCls = 'modal-bucket-count'
                + (count >= limit && !inThisBucket ? ' at' : '');

            ul.appendChild(el('li', {
                className: 'modal-bucket-item' + (rowState ? ' ' + rowState : '')
            }, [
                el('div', { className: 'modal-bucket-name' }, [
                    name,
                    isOther ? el('span', { className: 'bucket-tag' }, 'прочее') : null
                ]),
                el('div', { className: 'modal-bucket-section' }, isCantrip ? 'заговоры' : 'заклинания'),
                el('div', { className: countCls }, `${count} / ${limit}`),
                el('button', {
                    className: 'modal-bucket-add',
                    disabled: disabled ? 'disabled' : null,
                    title: btnTitle,
                    onClick: () => {
                        if (disabled) return;
                        if (count >= limit) return;
                        if (spellStatus(spell.id) !== null) return;
                        list.push(spell.id);
                        saveTracker();
                        closeDetailAddModal();
                        renderSpell(spell.id);
                    }
                }, btnText)
            ]));
        }
        listBox.appendChild(ul);
    }

    // ===== Tracker =====
    const TRACKER_KEY = 'spellTracker.v2';

    function newBucketId() {
        return 'b_' + Date.now().toString(36) + '_' + Math.random().toString(36).slice(2, 6);
    }

    function newBucket(name, cantripLimit, spellLimit) {
        return {
            id: newBucketId(),
            name: name || 'Класс',
            cantripLimit: cantripLimit ?? 3,
            spellLimit:   spellLimit   ?? 5,
            cantrips: [],
            spells:   []
        };
    }

    function defaultTracker() {
        return {
            buckets: [],
            other: {
                name: 'Прочее',
                cantripLimit: 0,
                spellLimit:   3,
                cantrips: [],
                spells:   []
            },
            otherVisible: false
        };
    }

    function loadTracker() {
        try {
            const raw = localStorage.getItem(TRACKER_KEY);
            if (!raw) return defaultTracker();
            const t = JSON.parse(raw);
            if (!t || !Array.isArray(t.buckets) || !t.other || typeof t.otherVisible !== 'boolean') {
                return defaultTracker();
            }
            for (const b of t.buckets) {
                if (b.cantripLimit == null) b.cantripLimit = 0;
                if (b.spellLimit   == null) b.spellLimit   = 0;
                if (!Array.isArray(b.cantrips)) b.cantrips = [];
                if (!Array.isArray(b.spells))   b.spells   = [];
            }
            const o = t.other;
            if (o.cantripLimit == null) o.cantripLimit = 0;
            if (o.spellLimit   == null) o.spellLimit   = 0;
            if (!Array.isArray(o.cantrips)) o.cantrips = [];
            if (!Array.isArray(o.spells))   o.spells   = [];
            return t;
        } catch (e) {
            console.warn('Failed to load tracker, using default:', e);
            return defaultTracker();
        }
    }

    function saveTracker() {
        try { localStorage.setItem(TRACKER_KEY, JSON.stringify(tracker)); }
        catch (e) { console.warn('Failed to save tracker:', e); }
    }

    let tracker = loadTracker();

    function spellStatus(spellId) {
        for (const b of tracker.buckets) {
            if (b.cantrips.includes(spellId) || b.spells.includes(spellId)) return 'visible';
        }
        if (tracker.other.cantrips.includes(spellId) || tracker.other.spells.includes(spellId)) {
            return tracker.otherVisible ? 'visible' : 'hidden';
        }
        return null;
    }

    function trackerTotals() {
        let count = 0, limit = 0;
        for (const b of tracker.buckets) {
            count += b.cantrips.length + b.spells.length;
            limit += (Number(b.cantripLimit) || 0) + (Number(b.spellLimit) || 0);
        }
        if (tracker.otherVisible) {
            count += tracker.other.cantrips.length + tracker.other.spells.length;
            limit += (Number(tracker.other.cantripLimit) || 0) + (Number(tracker.other.spellLimit) || 0);
        }
        return { count, limit };
    }

    const modalState = { bucket: null, kind: null, search: '' };

    function renderTracker() {
        const root = document.getElementById('content');
        root.innerHTML = '';

        const wrap = el('div', { className: 'tracker' });

        const head = el('div', { className: 'tracker-head' });
        head.appendChild(el('a', {
            className: 'back-link', href: '#/spells',
            onClick: (e) => { e.preventDefault(); navigate('/spells'); }
        }, '← К заклинаниям'));
        head.appendChild(el('button', {
            className: 'filter-reset tracker-reset',
            onClick: () => {
                if (confirm('Сбросить всю колоду? Все корзины и заклинания будут потеряны.')) {
                    tracker = defaultTracker();
                    saveTracker();
                    renderTracker();
                }
            }
        }, 'Сбросить всё'));
        wrap.appendChild(head);

        wrap.appendChild(el('h2', { className: 'spell-title tracker-title' }, 'Колода заклинаний'));

        const totals = trackerTotals();
        let summary = `Всего: ${totals.count} / ${totals.limit}`;
        const hiddenCount = tracker.other.cantrips.length + tracker.other.spells.length;
        if (!tracker.otherVisible && hiddenCount > 0) {
            summary += ` (+${hiddenCount} в скрытом «Прочее»)`;
        }
        wrap.appendChild(el('div', { className: 'tracker-summary' }, summary));

        wrap.appendChild(el('label', { className: 'tracker-other-toggle' }, [
            el('input', {
                type: 'checkbox',
                checked: tracker.otherVisible ? 'checked' : null,
                onChange: (e) => {
                    tracker.otherVisible = e.target.checked;
                    saveTracker();
                    renderTracker();
                }
            }),
            ' Показать «Прочее»'
        ]));

        tracker.buckets.forEach((b, i) => {
            wrap.appendChild(renderBucket(b, i, false));
        });
        if (tracker.otherVisible) {
            wrap.appendChild(renderBucket(tracker.other, -1, true));
        }

        wrap.appendChild(el('button', {
            className: 'tracker-add-bucket',
            onClick: () => {
                tracker.buckets.push(newBucket('Новый класс', 3, 5));
                saveTracker();
                renderTracker();
            }
        }, '+ Добавить класс'));

        root.appendChild(wrap);
    }

    function renderBucket(bucket, index, isOther) {
        const box = el('div', { className: 'tracker-bucket' + (isOther ? ' other' : '') });

        const head = el('div', { className: 'bucket-head' });
        if (isOther) {
            head.appendChild(el('span', { className: 'bucket-name bucket-name-fixed' }, 'Прочее'));
        } else {
            head.appendChild(el('input', {
                type: 'text', className: 'bucket-name', value: bucket.name,
                onInput: (e) => { bucket.name = e.target.value; saveTracker(); }
            }));
        }
        if (!isOther) {
            const spellCount = bucket.cantrips.length + bucket.spells.length;
            head.appendChild(el('button', {
                className: 'bucket-delete', title: 'Удалить класс',
                onClick: () => {
                    const msg = spellCount > 0
                        ? `Удалить «${bucket.name}»? Из него будет убрано ${spellCount} заклинаний.`
                        : `Удалить «${bucket.name}»?`;
                    if (!confirm(msg)) return;
                    tracker.buckets.splice(index, 1);
                    saveTracker();
                    renderTracker();
                }
            }, '×'));
        }
        box.appendChild(head);

        box.appendChild(renderBucketSection(bucket, 'cantrip'));
        box.appendChild(renderBucketSection(bucket, 'spell'));

        return box;
    }

    function renderBucketSection(bucket, kind) {
        const isCantrip = kind === 'cantrip';
        const list  = isCantrip ? bucket.cantrips : bucket.spells;
        const limit = isCantrip ? bucket.cantripLimit : bucket.spellLimit;
        const count = list.length;
        const over  = count > limit;
        const at    = count > 0 && count === limit;
        const full  = count >= limit;

        const sec = el('div', { className: 'bucket-section' });

        const h = el('div', { className: 'bucket-section-head' });
        h.appendChild(el('h4', null, isCantrip ? 'Заговоры' : 'Заклинания'));
        h.appendChild(el('span', {
            className: 'bucket-count' + (over ? ' over' : at ? ' at' : '')
        }, `${count} / ${limit}`));
        h.appendChild(el('label', { className: 'bucket-limit-wrap' }, [
            'лимит: ',
            el('input', {
                type: 'number', min: '0', className: 'bucket-limit',
                value: String(limit),
                onChange: (e) => {
                    const v = parseInt(e.target.value, 10);
                    const n = isNaN(v) || v < 0 ? 0 : v;
                    if (isCantrip) bucket.cantripLimit = n;
                    else           bucket.spellLimit  = n;
                    saveTracker();
                    renderTracker();
                }
            })
        ]));
        sec.appendChild(h);

        if (count === 0) {
            sec.appendChild(el('div', { className: 'bucket-empty' }, 'Пока пусто'));
        } else {
            const sorted = list.slice().sort((a, b) => {
                const sa = spellsById.get(a), sb = spellsById.get(b);
                const la = sa ? (sa.level ?? 99) : 99;
                const lb = sb ? (sb.level ?? 99) : 99;
                if (la !== lb) return la - lb;
                const na = sa ? ((sa.name && sa.name.ru) || '') : '';
                const nb = sb ? ((sb.name && sb.name.ru) || '') : '';
                return na.localeCompare(nb, 'ru');
            });

            const ul = el('ul', { className: 'bucket-list' });
            sorted.forEach((sid) => {
                const s = spellsById.get(sid);
                const name = s ? ((s.name && s.name.ru) || sid) : sid + ' (не найдено)';
                const nameNode = s
                    ? el('a', {
                        href: '#/spell/' + encodeURIComponent(s.id),
                        className: 'bucket-item-name'
                      }, name)
                    : el('span', { className: 'bucket-item-name' }, name);
                const meta = s ? `[${s.level}] ${s.school || ''}` : '';
                ul.appendChild(el('li', { className: 'bucket-item' }, [
                    nameNode,
                    el('span', { className: 'bucket-item-meta' }, meta),
                    el('button', {
                        className: 'bucket-item-remove', title: 'Убрать',
                        onClick: () => {
                            const idx = list.indexOf(sid);
                            if (idx >= 0) {
                                list.splice(idx, 1);
                                saveTracker();
                                renderTracker();
                            }
                        }
                    }, '×')
                ]));
            });
            sec.appendChild(ul);
        }

        sec.appendChild(el('button', {
            className: 'bucket-add',
            disabled: full ? 'disabled' : null,
            title: full
                ? (limit === 0 ? 'Нет слотов — задайте лимит' : 'Все слоты заняты')
                : (isCantrip ? 'Добавить заговор' : 'Добавить заклинание'),
            onClick: () => { if (!full) openAddModal(bucket, kind); }
        }, isCantrip ? '+ Добавить заговор' : '+ Добавить заклинание'));

        return sec;
    }

    function openAddModal(bucket, kind) {
        modalState.bucket = bucket;
        modalState.kind = kind;
        modalState.search = '';
        renderModal();
    }

    function closeModal() {
        modalState.bucket = null;
        modalState.kind = null;
        const m = document.getElementById('modal');
        if (m) m.remove();
        document.removeEventListener('keydown', onModalKey);
    }

    function onModalKey(e) { if (e.key === 'Escape') closeModal(); }

    function renderModal() {
        const old = document.getElementById('modal');
        if (old) old.remove();
        if (!modalState.bucket || !modalState.kind) return;

        const isCantrip = modalState.kind === 'cantrip';
        const bucket = modalState.bucket;

        const overlay = el('div', { id: 'modal', className: 'modal-overlay' });

        let downOnOverlay = false;
        overlay.addEventListener('mousedown', (e) => {
            downOnOverlay = (e.target === overlay);
        });
        overlay.addEventListener('mouseup', (e) => {
            if (downOnOverlay && e.target === overlay) closeModal();
            downOnOverlay = false;
        });

        const box = el('div', { className: 'modal-box' });
        box.appendChild(el('div', { className: 'modal-head' }, [
            el('h3', null, `${isCantrip ? 'Заговор' : 'Заклинание'} для «${bucket.name}»`),
            el('button', { className: 'modal-close', onClick: closeModal }, '×')
        ]));

        const searchInput = el('input', {
            type: 'search', className: 'modal-search', placeholder: 'Поиск…',
            value: modalState.search,
            onInput: (e) => { modalState.search = e.target.value; renderModalList(listBox); }
        });
        box.appendChild(searchInput);

        const listBox = el('div', { className: 'modal-list' });
        renderModalList(listBox);
        box.appendChild(listBox);

        overlay.appendChild(box);
        document.body.appendChild(overlay);
        document.addEventListener('keydown', onModalKey);
        setTimeout(() => searchInput.focus(), 0);
    }

    function renderModalList(listBox) {
        listBox.innerHTML = '';
        if (!modalState.bucket || !modalState.kind) return;

        const isCantrip = modalState.kind === 'cantrip';
        const bucket = modalState.bucket;
        const list  = isCantrip ? bucket.cantrips : bucket.spells;
        const limit = isCantrip ? bucket.cantripLimit : bucket.spellLimit;
        const atLimit = list.length >= limit;

        const q = modalState.search.toLowerCase().trim();

        const filtered = SPELLS.filter(s => {
            if (isCantrip) { if (s.level !== 0) return false; }
            else            { if (s.level == null || s.level < 1) return false; }
            if (q) {
                const ru = (s.name && s.name.ru || '').toLowerCase();
                const en = (s.name && s.name.en || '').toLowerCase();
                return ru.includes(q) || en.includes(q);
            }
            return true;
        });

        if (filtered.length === 0) {
            listBox.appendChild(el('div', { className: 'empty' }, 'Ничего не найдено'));
            return;
        }

        filtered.sort((a, b) => {
            if (!isCantrip) {
                const la = a.level ?? 99, lb = b.level ?? 99;
                if (la !== lb) return la - lb;
            }
            return ((a.name && a.name.ru) || '').localeCompare(
                   (b.name && b.name.ru) || '', 'ru');
        });

        const ul = el('ul', { className: 'modal-spell-list' });
        filtered.forEach(s => {
            const status  = spellStatus(s.id);
            const blocked = status !== null;
            const hidden  = status === 'hidden';
            const full    = !blocked && atLimit;

            let btnText, btnTitle;
            if (blocked)     { btnText = hidden ? '◦' : '✓'; btnTitle = hidden ? 'Уже в скрытом «Прочее»' : 'Уже в деке'; }
            else if (full)   { btnText = '–';                  btnTitle = 'Все слоты заняты'; }
            else             { btnText = '+';                  btnTitle = 'Добавить'; }

            const disabled = blocked || full;

            ul.appendChild(el('li', {
                className: 'modal-spell-item' + (blocked ? ' added' : '')
            }, [
                el('span', { className: 'spell-level' }, `[${s.level}]`),
                el('span', { className: 'spell-name' }, (s.name && s.name.ru) || '—'),
                el('span', { className: 'spell-school' }, s.school || ''),
                el('button', {
                    className: 'modal-spell-add',
                    disabled: disabled ? 'disabled' : null,
                    title: btnTitle,
                    onClick: () => {
                        if (disabled) return;
                        if (spellStatus(s.id) !== null) return;
                        if (list.length >= limit) return;
                        list.push(s.id);
                        saveTracker();
                        renderModalList(listBox);
                        renderTracker();
                    }
                }, btnText)
            ]));
        });
        listBox.appendChild(ul);
    }

// ===== Attunement (item tracker) =====
const ATTUNEMENT_KEY = 'itemAttunement.v1';

function defaultAttunement() {
    return {
        mysteriousFusion: false,
        artificer: false,
        artificerExtra: 1,
        slots: [null, null, null]
    };
}

function loadAttunement() {
    try {
        const raw = localStorage.getItem(ATTUNEMENT_KEY);
        if (!raw) return defaultAttunement();
        const a = JSON.parse(raw);
        if (!a || typeof a.mysteriousFusion !== 'boolean') return defaultAttunement();
        if (typeof a.artificer !== 'boolean') a.artificer = false;
        if (typeof a.artificerExtra !== 'number' || a.artificerExtra < 1 || a.artificerExtra > 3) {
            a.artificerExtra = 1;
        }
        if (!Array.isArray(a.slots)) a.slots = [];
        return a;
    } catch (e) {
        console.warn('Failed to load attunement, using default:', e);
        return defaultAttunement();
    }
}

function saveAttunement() {
    try { localStorage.setItem(ATTUNEMENT_KEY, JSON.stringify(attunement)); }
    catch (e) { console.warn('Failed to save attunement:', e); }
}

let attunement = loadAttunement();

function attunementTotalSlots() {
    let n = 3;
    if (attunement.mysteriousFusion) n += 1;
    if (attunement.artificer) n += attunement.artificerExtra;
    return n;
}

function syncAttunementSlots(showNotifications = true) {
    const target = attunementTotalSlots();
    const removedNames = [];
    while (attunement.slots.length < target) attunement.slots.push(null);
    while (attunement.slots.length > target) {
        const removed = attunement.slots.pop();
        if (removed) {
            const item = itemsById.get(removed);
            const name = item ? (item.name && item.name.ru) || removed : removed;
            removedNames.push(name);
        }
    }
    if (showNotifications) {
        if (removedNames.length === 1) {
            showToast(`Настройка с предмета «${removedNames[0]}» удалена`);
        } else if (removedNames.length > 1) {
            showToast(
                `Настройки со следующих предметов удалены: ` +
                removedNames.map(n => `«${n}»`).join(', ')
            );
        }
    }
}

// Silent sync on initial load (avoid toast if storage was somehow out of sync)
syncAttunementSlots(false);

function itemAttunementSlot(itemId) {
    return attunement.slots.indexOf(itemId);
}

function firstEmptyAttunementSlot() {
    return attunement.slots.indexOf(null);
}

function addItemToAttunement(itemId) {
    if (itemAttunementSlot(itemId) >= 0) return false;
    const idx = firstEmptyAttunementSlot();
    if (idx < 0) return false;
    attunement.slots[idx] = itemId;
    saveAttunement();
    return true;
}

function showToast(message, duration = 3500) {
    document.querySelectorAll('.toast').forEach(t => t.remove());
    const toast = el('div', { className: 'toast' }, message);
    document.body.appendChild(toast);
    requestAnimationFrame(() => toast.classList.add('show'));
    setTimeout(() => {
        toast.classList.remove('show');
        setTimeout(() => toast.remove(), 300);
    }, duration);
}

// --- Attunement view ---
function renderAttunement() {
    const root = document.getElementById('content');
    root.innerHTML = '';

    const wrap = el('div', { className: 'attunement' });

    const head = el('div', { className: 'tracker-head' });
    head.appendChild(el('a', {
        className: 'back-link', href: '#/items',
        onClick: (e) => { e.preventDefault(); navigate('/items'); }
    }, '← К предметам'));
    head.appendChild(el('button', {
        className: 'filter-reset tracker-reset',
        onClick: () => {
            if (confirm('Сбросить настройки? Все предметы будут удалены.')) {
                attunement = defaultAttunement();
                syncAttunementSlots(false);
                saveAttunement();
                renderAttunement();
            }
        }
    }, 'Сбросить всё'));
    wrap.appendChild(head);

    wrap.appendChild(el('h2', { className: 'spell-title tracker-title' }, 'Настройки'));

    const occupied = attunement.slots.filter(s => s !== null).length;
    const total = attunement.slots.length;
    wrap.appendChild(el('div', { className: 'tracker-summary' }, `Всего: ${occupied} / ${total}`));

    // Settings box
    const settings = el('div', { className: 'attunement-settings' });

    settings.appendChild(el('label', { className: 'attunement-toggle' }, [
        el('input', {
            type: 'checkbox',
            checked: attunement.mysteriousFusion ? 'checked' : null,
            onChange: (e) => {
                attunement.mysteriousFusion = e.target.checked;
                syncAttunementSlots();
                saveAttunement();
                renderAttunement();
            }
        }),
        ' Таинственное Слияние'
    ]));

    settings.appendChild(el('label', { className: 'attunement-toggle' }, [
        el('input', {
            type: 'checkbox',
            checked: attunement.artificer ? 'checked' : null,
            onChange: (e) => {
                attunement.artificer = e.target.checked;
                syncAttunementSlots();
                saveAttunement();
                renderAttunement();
            }
        }),
        ' Изобретатель'
    ]));

    if (attunement.artificer) {
        settings.appendChild(el('div', { className: 'attunement-slider-wrap' }, [
            el('label', null, [
                'Дополнительные слоты: ',
                el('strong', null, String(attunement.artificerExtra))
            ]),
            el('input', {
                type: 'range',
                min: '1', max: '3', step: '1',
                value: String(attunement.artificerExtra),
                className: 'attunement-slider',
                onInput: (e) => {
                    const v = parseInt(e.target.value, 10);
                    if (isNaN(v)) return;
                    attunement.artificerExtra = Math.max(1, Math.min(3, v));
                    syncAttunementSlots();
                    saveAttunement();
                    renderAttunement();
                }
            })
        ]));
    }

    wrap.appendChild(settings);

    // Slots
    const slotsWrap = el('div', { className: 'attunement-slots' });
    attunement.slots.forEach((itemId, i) => {
        slotsWrap.appendChild(renderAttunementSlot(i, itemId));
    });
    wrap.appendChild(slotsWrap);

    root.appendChild(wrap);
}

function renderAttunementSlot(index, itemId) {
    const box = el('div', { className: 'attunement-slot' });
    box.appendChild(el('div', { className: 'attunement-slot-label' }, `Слот ${index + 1}`));

    if (!itemId) {
        box.classList.add('empty');
        box.appendChild(el('button', {
            className: 'attunement-slot-add',
            onClick: () => openAttunementAddModal(index)
        }, '+ Добавить предмет'));
        return box;
    }

    const it = itemsById.get(itemId);

    if (!it) {
        box.classList.add('missing');
        box.appendChild(el('div', { className: 'attunement-slot-content' }, [
            el('span', { className: 'attunement-slot-name' }, `${itemId} (не найден)`),
            el('button', {
                className: 'attunement-slot-remove',
                onClick: () => {
                    attunement.slots[index] = null;
                    saveAttunement();
                    renderAttunement();
                }
            }, '×')
        ]));
        return box;
    }

    const name = (it.name && it.name.ru) || itemId;
    const typeText = it.type
        ? (it.prototype ? `${it.type} (${it.prototype})` : it.type)
        : '';

    box.appendChild(el('div', { className: 'attunement-slot-content' }, [
        el('div', { className: 'attunement-slot-info' }, [
            el('a', {
                className: 'attunement-slot-name',
                href: '#/item/' + encodeURIComponent(it.id)
            }, name),
            typeText ? el('span', { className: 'attunement-slot-type' }, typeText) : null
        ]),
        el('button', {
            className: 'attunement-slot-remove',
            title: 'Убрать из настроек',
            onClick: () => {
                attunement.slots[index] = null;
                saveAttunement();
                renderAttunement();
            }
        }, '×')
    ]));

    return box;
}

// --- Attunement: add item modal ---
const attunementModalState = { slot: null, search: '' };

function openAttunementAddModal(slotIndex) {
    attunementModalState.slot = slotIndex;
    attunementModalState.search = '';
    renderAttunementAddModal();
}

function closeAttunementAddModal() {
    attunementModalState.slot = null;
    const m = document.getElementById('modal');
    if (m) m.remove();
    document.removeEventListener('keydown', onAttunementModalKey);
}

function onAttunementModalKey(e) { if (e.key === 'Escape') closeAttunementAddModal(); }

function renderAttunementAddModal() {
    const old = document.getElementById('modal');
    if (old) old.remove();
    if (attunementModalState.slot === null) return;

    const slotIndex = attunementModalState.slot;
    const overlay = el('div', { id: 'modal', className: 'modal-overlay' });
    let downOnOverlay = false;
    overlay.addEventListener('mousedown', (e) => { downOnOverlay = (e.target === overlay); });
    overlay.addEventListener('mouseup', (e) => {
        if (downOnOverlay && e.target === overlay) closeAttunementAddModal();
        downOnOverlay = false;
    });

    const box = el('div', { className: 'modal-box modal-box-wide' });
    box.appendChild(el('div', { className: 'modal-head' }, [
        el('h3', null, `Добавить предмет в слот ${slotIndex + 1}`),
        el('button', { className: 'modal-close', onClick: closeAttunementAddModal }, '×')
    ]));

    box.appendChild(el('div', { className: 'modal-hint' },
        'Показаны только предметы, требующие настройки.'));

    const searchInput = el('input', {
        type: 'search', className: 'modal-search', placeholder: 'Поиск…',
        value: attunementModalState.search,
        onInput: (e) => { attunementModalState.search = e.target.value; renderAttunementAddList(listBox); }
    });
    box.appendChild(searchInput);

    const listBox = el('div', { className: 'modal-list' });
    renderAttunementAddList(listBox);
    box.appendChild(listBox);

    overlay.appendChild(box);
    document.body.appendChild(overlay);
    document.addEventListener('keydown', onAttunementModalKey);
    setTimeout(() => searchInput.focus(), 0);
}

function renderAttunementAddList(listBox) {
    listBox.innerHTML = '';
    if (attunementModalState.slot === null) return;

    const slotIndex = attunementModalState.slot;
    const q = attunementModalState.search.toLowerCase().trim();

    const filtered = ITEMS.filter(it => {
        if (!it.attunement) return false;
        if (!q) return true;
        const ru    = (it.name && it.name.ru || '').toLowerCase();
        const en    = (it.name && it.name.en || '').toLowerCase();
        const proto = (it.prototype || '').toLowerCase();
        return ru.includes(q) || en.includes(q) || proto.includes(q);
    });

    filtered.sort((a, b) =>
        ((a.name && a.name.ru) || '').localeCompare((b.name && b.name.ru) || '', 'ru'));

    if (filtered.length === 0) {
        listBox.appendChild(el('div', { className: 'empty' }, 'Ничего не найдено'));
        return;
    }

    const ul = el('ul', { className: 'modal-spell-list' });
    filtered.forEach(it => {
        const existingSlot = itemAttunementSlot(it.id);
        const blocked = existingSlot >= 0;
        const rk = itemRarityKey(it);
        const rarityText = it.rarity || ITEM_RARITY_LABELS[rk] || '';

        let btnText, btnTitle;
        if (blocked) { btnText = '✓'; btnTitle = `Уже в слоте ${existingSlot + 1}`; }
        else         { btnText = '+'; btnTitle = 'Добавить'; }

        ul.appendChild(el('li', {
            className: 'modal-attunement-item' + (blocked ? ' added' : '')
        }, [
            el('span', { className: 'item-type' }, it.type || '—'),
            el('span', { className: 'item-name' }, (it.name && it.name.ru) || '—'),
            el('span', { className: 'item-rarity rarity-' + rk }, rarityText),
            el('button', {
                className: 'modal-spell-add',
                disabled: blocked ? 'disabled' : null,
                title: btnTitle,
                onClick: () => {
                    if (blocked) return;
                    attunement.slots[slotIndex] = it.id;
                    saveAttunement();
                    closeAttunementAddModal();
                    renderAttunement();
                }
            }, btnText)
        ]));
    });
    listBox.appendChild(ul);
}

    // ===== Bootstrap =====
    document.getElementById('search').addEventListener('input', (e) => {
        state.search = e.target.value.trim();
        const r = parseRoute();
        if (r.view === 'spells')      renderSpellsList();
        else if (r.view === 'items')  renderItemsList();
        else                          navigate('/spells');
    });

    window.addEventListener('hashchange', render);
    render();
})();