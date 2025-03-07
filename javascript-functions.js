// Array difference a - b 
function difference(a, b) {
  return a.filter((x) => !b.some((y) => x == y));
};

export const saveBlob = (blob: any, fileName: string) => {
  const anchor = window.document.createElement("a");
  anchor.href = window.URL.createObjectURL(blob);
  anchor.download = fileName;
  document.body.appendChild(anchor);
  anchor.dispatchEvent(new MouseEvent("click"));
  document.body.removeChild(anchor);
  window.URL.revokeObjectURL(anchor.href);
};

export const trimJSONObj = (obj: any) => {
  if (obj === null || (!Array.isArray(obj) && typeof obj != "object")) return obj;
  return Object.keys(obj).reduce(
    function (acc: any, key) {
      acc[key.trim()] = typeof obj[key] == "string" ? obj[key].trim() : trimJSONObj(obj[key]);
      return acc;
    },
    Array.isArray(obj) ? [] : {}
  );
};

export function sortNestedObjectByKeys(obj: any = {}) {
  const newObj: any = sortObjectByKeys(obj);
  if (newObj) {
    Object.keys(newObj).forEach((key) => {
      if (typeof newObj[key] === "object") {
        newObj[key] = sortNestedObjectByKeys(obj[key]);
      } else if (Array.isArray(newObj[key])) {
        newObj[key] = obj[key].map((item: any) => {
          return sortNestedObjectByKeys(item);
        });
      }
    });
    return newObj;
  } else {
    return newObj;
  }
}
export function sortObjectByKeys(obj: any = {}) {
  if (obj) {
    return JSON.parse(JSON.stringify(obj, Object.keys(obj).sort()));
  } else {
    return obj;
  }
}

export function isObjectEqual(obj1: any = {}, obj2: any = {}) {
  obj1 = sortNestedObjectByKeys(obj1);
  obj2 = sortNestedObjectByKeys(obj2);
  return JSON.stringify(obj1) === JSON.stringify(obj2);
}

export const isClassComponent = (component: any) => {
  return typeof component === "function" && !!component?.prototype?.isReactComponent;
};

export const isFunctionalComponent = (component: any) => {
  return (
    typeof component === "function" && String(component).includes("return React.createElement")
  );
};

export const isReactComponent = (component: any) => {
  return (
    isClassComponent(component) ||
    isFunctionalComponent(component) ||
    !React.isValidElement(component)
  );
};

export function escapeHtml(html: string) {
  const div = document.createElement("div");
  div.appendChild(document.createTextNode(html));
  const htmlText = div.innerHTML;
  div.remove();
  return htmlText;
}

export const objectHasAny = (obj: any, predicate: (obj: any) => any): boolean => {
  if (Array.isArray(obj)) {
    const result = obj.some((item) => objectHasAny(item, predicate));
    return result;
  } else if (typeof obj === "object" && obj !== null && obj !== undefined) {
    let result = predicate(obj);
    if (result) {
      return true;
    } else {
      return Object.values(obj).some((value) => objectHasAny(value, predicate));
    }
  }
  return false;
};

// converts firstName to First Name, rxBIN to Rx BIN.
export function camelCaseToTitleCase(str) {
  return str
    .replace(/([a-z])([A-Z])/g, "$1 $2")
    .replace(/([A-Z]+)([A-Z][a-z])/g, "$1 $2")
    .replace(/\b[a-z]/g, (char) => char.toUpperCase());
}

// converts file selected in browser for upload to base64 string
export function convertFileToBase64 = (file: File) => {
  return new Promise<string>((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => {
      resolve(reader.result as string);
    };
    reader.onerror = reject;
    reader.readAsDataURL(file);
  });
};
