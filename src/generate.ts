import * as fs from 'fs';
import * as path from 'path';
import * as ejs from 'ejs';

const ROOT_DIR = path.join(__dirname, '..');
const SCHEMA_PATH = path.join(ROOT_DIR, 'schema', 'fablo-config-fabricx.json');
const TEMPLATES_DIR = path.join(ROOT_DIR, 'templates');
const OUTPUT_DIR = path.join(ROOT_DIR, 'generated-output');

function readJsonFile(filePath: string): any {
  const content = fs.readFileSync(filePath, 'utf8');
  return JSON.parse(content);
}

function generate() {
  console.log('Starting Fabric-X configuration generation...');
  
  if (fs.existsSync(OUTPUT_DIR)) {
    fs.rmSync(OUTPUT_DIR, { recursive: true, force: true });
  }
  fs.mkdirSync(OUTPUT_DIR, { recursive: true });

  const config = readJsonFile(SCHEMA_PATH);
  
  const dockerComposeTemplate = fs.readFileSync(path.join(TEMPLATES_DIR, 'docker-compose-fabricx.ejs'), 'utf8');
  const coreYamlTemplate = fs.readFileSync(path.join(TEMPLATES_DIR, 'fsc-core-yaml.ejs'), 'utf8');
  const routingConfigTemplate = fs.readFileSync(path.join(TEMPLATES_DIR, 'routing-config.ejs'), 'utf8');

  // Find committer
  let committer: any = null;
  let defaultCommitterName = 'committer-test-node';
  for (const org of config.orgs) {
    if (org.committers && org.committers.length > 0) {
      committer = org.committers[0];
      defaultCommitterName = committer.name;
      break;
    }
  }

  // Process all FSC nodes
  let allFscNodes: any[] = [];
  for (const org of config.orgs) {
    if (org.endorsers) {
      for (const end of org.endorsers) {
         allFscNodes.push({ ...end, domain: org.organization.domain, org: org.organization, orgContext: org });
      }
    }
    if (org.fscNodes) {
        for (const node of org.fscNodes) {
           allFscNodes.push({ ...node, domain: node.domain || org.organization.domain, org: org.organization, orgContext: org });
        }
    }
  }

  // sort priority
  const rolePriority: Record<string, number> = { 'issuer': 0, 'auditor': 1, 'endorser': 2, 'owner': 3 };
  allFscNodes.sort((a, b) => {
    let pa = rolePriority[a.role] ?? 999;
    let pb = rolePriority[b.role] ?? 999;
    if (pa !== pb) return pa - pb;
    return a.name.localeCompare(b.name);
  });

  let endorserCount = 0;
  for (let i = 0; i < allFscNodes.length; i++) {
    const node = allFscNodes[i];
    node.ports = {
      api: 9100 + (i * 100),
      p2p: 9100 + (i * 100) + 1
    };
    node.excludeFromResolvers = (node.role === 'auditor');
    if (node.role === 'endorser') {
      endorserCount++;
      if (endorserCount === 1) {
        node.peerUsage = '';
        node.hasPublicParameters = true;
      } else {
        node.peerUsage = 'delivery';
        node.hasPublicParameters = false;
      }
    } else {
      node.peerUsage = 'delivery';
      node.hasPublicParameters = false;
    }
    node.fabricMspId = (node.role === 'endorser') ? 'endorser' : 'user';
    node.isEndorser = (node.role === 'endorser');
    if (!node.fsc) node.fsc = {};
    node.fsc.id = node.name;
    node.fsc.p2pListenAddress = `/ip4/0.0.0.0/tcp/${node.ports.p2p}`;
    if (!node.fsc.driver) node.fsc.driver = 'fabricx';
    if (!node.nodeType) node.nodeType = node.role; 
    if (!node.db) {
       node.db = { type: 'sqlite', datasource: `file:./data/fts.sqlite` };
    }
    if (!node.committerName) {
        node.committerName = node.orgContext && node.orgContext.committers && node.orgContext.committers.length > 0 ? node.orgContext.committers[0].name : defaultCommitterName;
    }
  }

  // Generate Docker Compose
  let dockerComposeContent = ejs.render(dockerComposeTemplate, { config, global: config.global, orgs: config.orgs, allFscNodes });
  dockerComposeContent = dockerComposeContent.replace(/\n{3,}/g, '\n\n');
  fs.writeFileSync(path.join(OUTPUT_DIR, 'docker-compose.yml'), dockerComposeContent);
  console.log(' ✓ Generated docker-compose.yml');

  const channelName = config.channels[0].name;

  // Next, loop over ALL nodes to generate config files
  for (const node of allFscNodes) {
    const nodeDir = path.join(OUTPUT_DIR, 'conf', node.name);
    fs.mkdirSync(nodeDir, { recursive: true });

    const nodeContext = {
      node: node,
      allFscNodes,
      committer,
      channelName
    };

    const coreYamlContent = ejs.render(coreYamlTemplate, nodeContext);
    fs.writeFileSync(path.join(nodeDir, 'core.yaml'), coreYamlContent);
    console.log(` ✓ Generated conf/${node.name}/core.yaml`);

    const routingConfigContent = ejs.render(routingConfigTemplate, nodeContext);
    fs.writeFileSync(path.join(nodeDir, 'routing-config.yaml'), routingConfigContent);
    console.log(` ✓ Generated conf/${node.name}/routing-config.yaml`);
  }

  console.log('Generation completed successfully!');
}

try {
  generate();
} catch (error) {
  console.error('Error generating configuration:', error);
  process.exit(1);
}
