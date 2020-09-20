export default class DataSheetBase {
  constructor(id, updateCb) {
    this.id = id;
    this.updateCb = updateCb;
    this.items = [];
    this.requestedKeyPath = '';

    this.makeDefaultItems();
  }

  makeDefaultItems() {
    // subclasses can override
  }


  // -- these methods will typically be overridden in a subclass by a React Studio web service plugin.
  //    'options' is an optional value that should be passed to a React Studio provided callback by a plugin implementer.
  //    it can be used to identify async writes by caller code.

  addItem(item, options) {
    let key = 1;
    if (this.items.length > 0) {
      key += this.items[this.items.length - 1].key;
    }
    item.key = key;
    this.items.push(item);
  }

  removeItem(item, options) {
    this.items = this.items.filter(i => i.key !== item.key);
  }

  replaceItemByRowIndex(idx, newItem, options) {
    if (idx < 0 || idx >= this.items.length)
      return;
    this.items.splice(idx, 1, newItem);
  }

  replaceItemByKey(key, newItem, options) {
    // this is the method that gets called for updates.
    // a subclasser can override this method instead of the 'byRowIndex' variant if needed.
    const idx = this.rowIndexForKey(key);
    if (idx < 0)
      return;
    this.replaceItemByRowIndex(idx, newItem, options);
  }


  // -- utility methods

  rowIndexForKey(key) {
    for (let i = 0; i < this.items.length; i++) {
      if (this.items[i].key === key)
        return i;
    }
    return -1;
  }

  loadFromJson(json) {
    function setupArrayKeys(json) {
      // for an array, ensure that items have a key (this is required by React)
      for (var i = 0; i < json.length; i++) {
        if (json[i].key === undefined)
          json[i].key = i;
      }
    }

    if (Array.isArray(json)) {
      setupArrayKeys(json);
      this.items = json;
    }
    else if (json) {
      // if we received a single JSON object, set it as the first row in the sheet.
      // if there's a keypath specified, look up that first.
      var keyPath = this.requestedKeyPath;
      if ( !keyPath || keyPath.length < 1) {
        if ( !json.key) json.key = 0;
        this.items = [ json ];
      } else {
        // look for the requested key path within this object
        var pathComps = keyPath.split('.');
        for (var comp of pathComps) {
          if ( !json.hasOwnProperty(comp)) break;
          json = json[comp];
        }
        if (Array.isArray(json)) {
          setupArrayKeys(json);
          this.items = json;
        } else {
          if ( !json.key) json.key = 0;
          this.items = [ json ];
        }
      }
    }
    else {
      this.items = [];
    }
  }

  expandSlotTemplateString(query, slots, outUsedSlotsArray /*optional*/) {
    // this method parses the tiny template format offered in React Studio's data sheet settings.
    // these template strings can contain references to data slot values, like this:
    //
    //     page=$slot('someDataSlot')&username=$slot('anotherDataSlot')

    if (query.length < 1)
      return "";

    let scanIndex = 0;
    let expanded = "";
    while (scanIndex < query.length) {
      let index = query.indexOf("$slot(", scanIndex);
      if (index === -1) {
        index = query.length;
      }
      expanded += query.substring(scanIndex, index);
      scanIndex = index;

      if (index === query.length)
        break;

      scanIndex += "$slot(".length;

      index = query.indexOf(")", scanIndex);
      if (index !== -1) {
        let slotRefStr = query.substring(scanIndex, index);
        const firstChar = slotRefStr.charAt(0);
        if (firstChar === '\'' || firstChar === '"') {
          slotRefStr = slotRefStr.substring(1, slotRefStr.length - 1);
        }
        const slotValue = slots[slotRefStr] || '';
        expanded += slotValue;

        index += ')'.length;

        if (outUsedSlotsArray && !outUsedSlotsArray.includes(slotRefStr)) {
          outUsedSlotsArray.push(slotRefStr);
        }
      }
      scanIndex = (index === -1) ? query.length : index;
    }
    return expanded;
  }

}
