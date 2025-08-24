public static class JsonMerge
{
    private static bool IsValidJson(string str)
    {
        try
        {
            JToken.Parse(str);
            return true;
        }
        catch
        {
            return false;
        }
    }

    public static JToken DeepMerge(JToken target, JToken source)
    {
        if (source.Type == JTokenType.Object)
        {
            var targetObj = target.Type == JTokenType.Object ? (JObject)target : new JObject();
			var srcObj = (JObject)source;
			
			if (srcObj["_id"] == null)
				srcObj["_id"] = Guid.NewGuid().ToString();
			
            foreach (var prop in ((JObject)source).Properties())
            {
                if (prop.Name == "_deleted" && prop.Value.Type == JTokenType.Boolean && (bool)prop.Value)
                {
                    targetObj.Remove(prop.Name);
                    continue;
                }
				
				targetObj[prop.Name] = prop.Value.Type == JTokenType.Object || prop.Value.Type == JTokenType.Array
					? DeepMerge(targetObj[prop.Name] ?? new JObject(), prop.Value)
					: prop.Value;
            }
            return targetObj;
        }
        else 
        {
            var targetArr = target.Type == JTokenType.Array ? (JArray)target : new JArray();
            var sourceArr = (JArray)source;

            foreach (var srcItem in sourceArr)
            {
                JObject srcObj = srcItem as JObject;

                if (srcObj != null)
                {
                    if (srcObj["_id"] == null)
                        srcObj["_id"] = Guid.NewGuid().ToString();
					
					var existing = targetArr.FirstOrDefault(t => t["_id"] != null && t["_id"].ToString() == srcObj["_id"].ToString());
					
					if (existing != null) {
						if (srcObj["_deleted"] != null && srcObj["_deleted"].Type == JTokenType.Boolean && (bool)srcObj["_deleted"]) {
							targetArr.Remove(existing);
							continue;
						}
						DeepMerge(existing, srcObj);
					} else {
						targetArr.Add(srcObj);
					}
                }
            }

            return targetArr;
        }
    }
}
