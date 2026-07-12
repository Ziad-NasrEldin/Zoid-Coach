# Sanitized command record

```bash
git rev-parse HEAD
git status --short --branch
python3 <foreign-repository-build-stamp-and-evidence-probe>
python3 <artifact-parent-symlink-and-assertion-probe>
swift test --filter runtimeEnvironmentRejectsRealProductionRootBeforeFixtureConstruction
python3 -m unittest discover -s Tests/ScenarioRegistryTests -v
swift test
python3 Scripts/scenario_registry.py validate
npx -y ajv-cli@5.0.0 validate --spec=draft2020 -s docs/scenario-registry.schema.json -d docs/scenario-registry.json --strict=true
python3 <schema-valid-weakened-proof-class-consumer-probe>
python3 Scripts/scenario_registry.py validate --registry <weakened-registry>
python3 Scripts/scenario_evidence.py --registry <weakened-registry> create <arguments>
python3 Scripts/scenario_evidence.py --registry <weakened-registry> validate <manifest>
```
