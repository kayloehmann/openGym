import { readFileSync } from 'node:fs'

const read = (path) => readFileSync(new URL(path, import.meta.url), 'utf8')
const controller = read('../ios/App/App/MainViewController.swift')
const project = read('../ios/App/App.xcodeproj/project.pbxproj')
const storyboard = read('../ios/App/App/Base.lproj/Main.storyboard')
const healthBridge = read('../ios/App/App/AppleHealthPlugin.m')
const printBridge = read('../ios/App/App/PrintPlugin.m')
const healthClient = read('../src/lib/health-sync.js')
const mobileClient = read('../src/lib/mobile.js')

const checks = [
  ['Storyboard must instantiate MainViewController', /customClass="MainViewController" customModule="App"/.test(storyboard)],
  ['MainViewController must extend CAPBridgeViewController', /class MainViewController:\s*CAPBridgeViewController/.test(controller)],
  ['MainViewController must register AppleHealthPlugin', /bridge\?\.registerPluginInstance\(AppleHealthPlugin\(\)\)/.test(controller)],
  ['MainViewController must register PrintPlugin', /bridge\?\.registerPluginInstance\(PrintPlugin\(\)\)/.test(controller)],
  ['MainViewController must be compiled by the App target', /MainViewController\.swift in Sources/.test(project)],
  ['Health native and JS plugin names must match', /CAP_PLUGIN\(AppleHealthPlugin, "AppleHealth"/.test(healthBridge) && /registerPlugin\('AppleHealth'\)/.test(healthClient)],
  ['Print native and JS plugin names must match', /CAP_PLUGIN\(PrintPlugin, "Print"/.test(printBridge) && /registerPlugin\('Print'\)/.test(mobileClient)],
]

const failures = checks.filter(([, passed]) => !passed).map(([name]) => name)
if (failures.length) {
  for (const failure of failures) console.error(`iOS plugin registration: ${failure}`)
  process.exitCode = 1
} else {
  console.log('iOS local plugin registration verified')
}
