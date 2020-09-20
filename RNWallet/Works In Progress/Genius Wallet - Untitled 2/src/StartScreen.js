import React, { Component } from 'react';
import './App.css';
import btn_icon_237929 from './images/btn_icon_237929.png';

// UI framework component imports
import Select from 'muicss/lib/react/select';
import Option from 'muicss/lib/react/option';
import Button from 'muicss/lib/react/button';

export default class StartScreen extends Component {

  // Properties used by this component:
  // appActions, deviceInfo

  constructor(props) {
    super(props);
    
    this.state = {
      picker: '',
    };
  }

  componentDidMount() {
  }

  componentWillUnmount() {
  }

  componentDidUpdate() {
  }

  pickerValueChanged_picker = (event) => {
    this.setState({picker: event.target.value});
  }
  
  render() {
    let layoutFlowStyle = {};
    let baseStyle = {};
    if (this.props.transitionId && this.props.transitionId.length > 0 && this.props.atTopOfScreenStack && this.props.transitionForward) {
      baseStyle.animation = '0.25s ease-in-out '+this.props.transitionId;
    }
    if ( !this.props.atTopOfScreenStack) {
      layoutFlowStyle.height = '100vh';
      layoutFlowStyle.overflow = 'hidden';
    }
    
    const style_elBackground = {
      width: '100%',
      height: '100%',
     };
    const style_elBackground_outer = {
      backgroundColor: '#f6f6f6',
     };
    
    let selection_picker = this.state.picker;
    
    const style_elPicker = {
      pointerEvents: 'auto',
     };
    
    const style_elFab = {
      display: 'block',
      color: '(null)',
      textAlign: 'left',
     };
    
    return (
      <div className="AppScreen StartScreen" style={baseStyle}>
        <div className="background">
          <div className="containerMinHeight elBackground" style={style_elBackground_outer}>
            <div className="appBg" style={style_elBackground} />
          </div>
        </div>
        
        <div className="layoutFlow" style={layoutFlowStyle}>
          <div className="elPicker">
            <Select className="baseFont" style={style_elPicker}  onChange={this.pickerValueChanged_picker} value={selection_picker}  />
          </div>
          
          <div className="elFab">
            <Button className="actionFont" style={style_elFab}  variant="fab" color="accent" >
              <img src={btn_icon_237929} alt="" style={{width: '100%', marginTop: '4%'}} />
            </Button>
          </div>
        </div>
        
      </div>
    )
  }
  
}
