# Prediction target

Given `realm-config.json` and `request.json`, what is the value of the `collision_claim` claim in the resulting access-token payload?

The skill must commit to one of the following shapes (or to "the claim is absent"), with a single concrete value where applicable. Hedges of the form "depends on order," "either A or B," "the last-applied mapper wins" without naming which mapper is last-applied, or "implementation-defined" do not count as predictions.

- `"value-from-alpha"` (string, exact)
- `"value-from-zulu"` (string, exact)
- `["value-from-alpha", "value-from-zulu"]` or `["value-from-zulu", "value-from-alpha"]` (array; element order matters)
- claim absent from `access_token` payload entirely
